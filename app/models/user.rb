require 'digest/sha1'
class User < ActiveRecord::Base
  # Virtual attribute for the unencrypted password
  attr_accessor :password

  serialize :block_users

  validates_presence_of     :login, :email
  validates_presence_of     :password,                   :if => :password_required?
  validates_presence_of     :password_confirmation,      :if => :password_required?
  validates_length_of       :password, :within => 4..40, :if => :password_required?
  validates_confirmation_of :password,                   :if => :password_required?
  validates_length_of       :login,    :within => 3..40
  validates_length_of       :email,    :within => 3..100
  validates_uniqueness_of   :login, :email, :case_sensitive => false
  
  validates_format_of       :color, :with => /^(\#([0-9a-fA-F]{6}))?$/
  
  before_save :encrypt_password
  
  before_create :make_activation_code 
  before_create :set_display_name
  # prevents a user from submitting a crafted form that bypasses activation
  # anything else you want your user to change should be added here.
  attr_accessible :login, :email, :password, :password_confirmation, :color, :display_name, :stylesheet_id
  
  after_create :create_private_channel
  
  has_many :posts
  has_many :channel_visits
  has_many :uploads
  
  has_many :messages
  has_many :unread_messages, :class_name => "Message", :conditions => "status = #{Message::STATUS_UNREAD}"
  
  belongs_to :stylesheet

  # Activates the user in the database.
  def activate
    @activated = true
    self.activated_at = Time.now.utc
    self.activation_code = nil
    save(false)
  end
  
  def can_invite?
    id == 1
  end
  
  def set_display_name
    self.display_name = login
  end
  
  def private_channel
    Channel.find(:first, :conditions => ["user_id = ? AND title = ? AND default_read = ?", id, "#{login}/Mailbox", false])
  end

  def active?
    # the existence of an activation code means they have not activated yet
    activation_code.nil?
  end

  # Returns true if the user has just been activated.
  def pending?
    @activated
  end
  
  def self.all_users
    self.find(:all, :order => "LOWER(display_name)")
  end

  # Authenticates a user by their login name and unencrypted password.  Returns the user or nil.
  def self.authenticate(login, password)
    u = find :first, :conditions => ['LOWER(login) = LOWER(?) and activated_at IS NOT NULL', login] # need to get the salt
    u && u.authenticated?(password) ? u : nil
  end

  # Encrypts some data with the salt.
  def self.encrypt(password, salt)
    Digest::SHA1.hexdigest("--#{salt}--#{password}--")
  end

  # Encrypts the password with the user salt
  def encrypt(password)
    self.class.encrypt(password, salt)
  end

  def authenticated?(password)
    crypted_password == encrypt(password)
  end

  def remember_token?
    remember_token_expires_at && Time.now.utc < remember_token_expires_at 
  end

  # These create and unset the fields required for remembering users between browser closes
  def remember_me
    remember_me_for 2.weeks
  end

  def remember_me_for(time)
    remember_me_until time.from_now.utc
  end

  def remember_me_until(time)
    self.remember_token_expires_at = time
    self.remember_token            = encrypt("#{email}--#{remember_token_expires_at}")
    save(false)
  end

  def forget_me
    self.remember_token_expires_at = nil
    self.remember_token            = nil
    save(false)
  end
  
  def create_private_channel
    Channel.create(:title => "#{login}/Mailbox", :user_id => id, :default_read => false, :default_write => true)
  end
  
  def display_color
    "color: #{color}" unless color.blank?
  end
  
  def update_message_counter
    self.number_unread_messages = unread_messages.count
    save
  end

  def block_user(u)
    self.block_users ||= []
    self.block_users << u.id.to_i
  end

  protected
    # before filter 
    def encrypt_password
      return if password.blank?
      self.salt = Digest::SHA1.hexdigest("--#{Time.now.to_s}--#{login}--") if new_record?
      self.crypted_password = encrypt(password)
    end
      
    def password_required?
      crypted_password.blank? || !password.blank?
    end
    
    def make_activation_code

      self.activation_code = Digest::SHA1.hexdigest( Time.now.to_s.split(//).sort_by {rand}.join )
    end
    
end
