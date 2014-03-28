class Tip < ActiveRecord::Base
  belongs_to :user
  belongs_to :sendmany
  belongs_to :project, inverse_of: :tips

  validates :amount, numericality: {greater_or_equal_than: 0, allow_nil: true}

  scope :not_sent,      -> { where(sendmany_id: nil) }
  def not_sent?
    sendmany_id.nil?
  end

  scope :unpaid,        -> { non_refunded.not_sent }
  def unpaid?
    non_refunded? and not_sent?
  end

  scope :to_pay,        -> { unpaid.decided.not_free.with_address }
  def to_pay?
    unpaid? and decided? and !free? and with_address?
  end

  scope :free,          -> { where('amount = 0') }
  scope :not_free,      -> { where('amount > 0') }
  def free?
    amount == 0
  end

  scope :paid,          -> { where('sendmany_id is not ?', nil) }
  def paid?
    !!sendmany_id
  end

  scope :refunded,      -> { where('refunded_at is not ?', nil) }
  scope :non_refunded,  -> { where(refunded_at: nil) }
  def refunded?
    !!refunded_at
  end
  def non_refunded?
    !refunded?
  end

  scope :unclaimed,     -> { joins(:user).
                             unpaid.
                             where('users.bitcoin_address' => ['', nil]) }

  scope :with_address,  -> { joins(:user).where('users.bitcoin_address IS NOT NULL AND users.bitcoin_address != ?', "") }
  def with_address?
    user.bitcoin_address.present?
  end

  scope :decided,       -> { where.not(amount: nil) }
  scope :undecided,     -> { where(amount: nil) }
  def decided?
    !!amount
  end
  def undecided?
    !decided?
  end


  before_save :check_amount_against_project
  after_save :notify_user_if_just_decided


  def self.refund_unclaimed
    unclaimed.non_refunded.
    where('tips.created_at < ?', Time.now - 1.month).
    find_each do |tip|
      tip.touch :refunded_at
    end
  end

  def commit_url
    project.commit_url(commit)
  end

  def amount_percentage
    nil
  end

  def amount_percentage=(percentage)
    if undecided? and percentage.present?
      self.amount = project.available_amount * (percentage.to_f / 100)
    end
  end

  def notify_user
    if amount and amount > 0 and user.bitcoin_address.blank? and !user.unsubscribed
      if user.notified_at.nil? or user.notified_at < 30.days.ago
        UserMailer.new_tip(user, self).deliver
        user.touch :notified_at
      end
    end
  end

  def notify_user_if_just_decided
    notify_user if amount_was.nil? and amount
  end

  def check_amount_against_project
    if amount
      available_amount = project.available_amount
      available_amount -= amount_was if amount_was
      if amount > available_amount
        raise "Not enough funds on project to save #{inspect} (available: #{available_amount})"
      end
    end
  end
end
