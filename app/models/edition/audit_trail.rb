module Edition::AuditTrail
  extend ActiveSupport::Concern

  class << self
    attr_accessor :whodunnit
  end

  def self.acting_as(actor)
    original_actor = Edition::AuditTrail.whodunnit
    Edition::AuditTrail.whodunnit = actor
    yield
  ensure
    Edition::AuditTrail.whodunnit = original_actor
  end

  included do
    has_many :versions, -> { order("created_at ASC, id ASC") }, as: :item

    has_one :most_recent_version,
            -> { order("versions.created_at DESC, versions.id DESC") },
            class_name: "Version",
            as: :item
    has_one :last_author,
            through: :most_recent_version,
            source: :user

    after_create  :record_create
    before_update :record_update
  end

  def versions_asc
    versions
  end

  def versions_desc
    versions.reverse_order
  end

  def edition_remarks_trail(edition_serial_number = 0)
    editorial_remarks.map { |r|
      EditorialRemarkAuditEntry.new(edition_serial_number, self, r)
    }.sort
  end

  def edition_version_trail(edition_serial_number = 0, superseded: true)
    scope = versions
    scope = scope.where.not(state: "superseded") unless superseded

    scope.map { |v|
      VersionAuditEntry.new(edition_serial_number, self, v)
    }.sort
  end

  def document_remarks_trail(superseded: true)
    document_trail(superseded: superseded, remarks: true)
  end

  def document_version_trail(superseded: true, limit: false)
    scope = document_versions.reverse_order
    scope = scope.where.not(state: "superseded") unless superseded
    scope = scope.limit(limit) if limit

    first_version = document_versions.first

    scope.reverse.map do |version|
      # Temporary bastardisation of the edition_serial_number to avoid refactoring first_edition? method and breaking EditorialRemarkAuditEntry
      edition_serial_number = if version == first_version
                                0
                              else
                                1
                              end
      VersionAuditEntry.new(edition_serial_number, version.item, version)
    end
  end

  def publication_audit_entry
    version = document_versions.where(state: "published").first
    VersionAuditEntry.new(0, version.item, version)
  end

private

  def document_versions
    Version.where(item_type: "Edition", item_id: document.editions.select(:id))
           .includes(:item, :user)
           .order(created_at: :asc, id: :asc)
  end

  def record_create
    user = Edition::AuditTrail.whodunnit
    versions.create! event: "create", user: user, state: state
    alert!(user)
  end

  def record_update
    if changed.any?
      user = Edition::AuditTrail.whodunnit
      versions.build event: "update", user: user, state: state
      alert!(user)
    end
  end

  def alert!(user)
    if user && should_alert_for?(user)
      ::MailNotifications.edition_published_by_monitored_user(user).deliver_now
    end
  end

  def should_alert_for?(user)
    ENV["CO_NSS_WATCHKEEPER_EMAIL_ADDRESS"].present? &&
      user.email == ENV["CO_NSS_WATCHKEEPER_EMAIL_ADDRESS"]
  end

  def document_trail(superseded: true, limit: false, versions: false, remarks: false)
    scope = document.editions

    # Temporary fix to limit history on document:
    # /government/publications/royal-courts-of-justice-cause-list
    # which is known to cause timeouts due to the size of its history
    if document.content_id == "c7346901-13fe-47df-a1f0-b583b78bf6e7"
      scope = scope.order("first_published_at ASC").limit(3)
    end

    scope = scope.includes(versions: [:user]) if versions
    scope = scope.includes(editorial_remarks: [:author]) if remarks

    if versions
      scope = Version.where(item_type: "Edition", item_id: document.editions.select(:id))
      scope = scope.where.not(state: "superseded") unless superseded

      return scope.includes(:item, :user)
                  .order("created_at desc, id desc")
                  .limit(limit)
                  .reverse
                  .map.with_index { |version, i| VersionAuditEntry.new(i, version.item, version) }
    end

    scope
      .includes(versions: [:user])
      .order("created_at asc, id asc")
      .map.with_index { |edition, i|
        [
          (edition.edition_version_trail(i, superseded: superseded) if versions),
          (edition.edition_remarks_trail(i) if remarks),
        ].compact
      }.flatten
  end

  class AuditEntry
    extend ActiveModel::Naming

    delegate :created_at, :to_key, to: :@object

    attr_reader :edition_serial_number, :edition, :object

    def initialize(edition_serial_number, edition, object)
      @edition_serial_number = edition_serial_number
      @edition = edition
      @object = object
    end

    def <=>(other)
      [created_at, sort_priority] <=> [other.created_at, other.sort_priority]
    end

    def ==(other)
      other.class == self.class &&
        other.edition_serial_number == edition_serial_number &&
        other.edition == edition &&
        other.object == object
    end

    def first_edition?
      edition_serial_number.zero?
    end

    def sort_priority
      0
    end
  end

  class VersionAuditEntry < AuditEntry
    def self.model_name
      ActiveModel::Name.new(Version, nil)
    end

    alias_method :version, :object

    def sort_priority
      3
    end

    def action
      previous_state = version.previous && version.previous.state
      case version.event
      when "create"
        first_edition? ? "created" : "editioned"
      else
        previous_state != version.state ? version.state : "updated"
      end
    end

    def actor
      version.user
    end
  end

  class EditorialRemarkAuditEntry < AuditEntry
    def self.model_name
      ActiveModel::Name.new(EditorialRemark, nil)
    end

    alias_method :editorial_remark, :object

    def action
      "editorial_remark"
    end

    def actor
      editorial_remark.author
    end

    def message
      editorial_remark.body
    end

    def sort_priority
      2
    end
  end
end
