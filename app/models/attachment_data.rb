require "pdf-reader"
require "timeout"

class AttachmentData < ApplicationRecord
  mount_uploader :file, AttachmentUploader, mount_on: :carrierwave_file

  has_many :attachments, -> { order(:attachable_id) }, inverse_of: :attachment_data

  delegate :url, :path, to: :file, allow_nil: true

  before_save :update_file_attributes

  validates :file, presence: true
  validate :file_is_not_empty

  attr_accessor :to_replace_id, :attachable

  belongs_to :replaced_by, class_name: "AttachmentData"
  validate :cant_be_replaced_by_self
  after_save :handle_to_replace_id

  OPENDOCUMENT_EXTENSIONS = %w[ODT ODP ODS].freeze

  attribute :present_at_unpublish, :boolean, default: false

  def filename
    url && File.basename(url)
  end

  def filename_without_extension
    url && filename.sub(/.[^.]*$/, "")
  end

  def file_extension
    File.extname(url).delete(".") if url.present?
  end

  def pdf?
    content_type == AttachmentUploader::PDF_CONTENT_TYPE
  end

  def txt?
    file_extension == "txt"
  end

  def csv?
    file_extension.casecmp("csv").zero?
  end

  # Is in OpenDocument format? (see https://en.wikipedia.org/wiki/OpenDocument)
  def opendocument?
    OPENDOCUMENT_EXTENSIONS.include? file_extension.upcase
  end

  def indexable?
    AttachmentUploader::INDEXABLE_TYPES.include?(file_extension)
  end

  def update_file_attributes
    if carrierwave_file.present? && carrierwave_file_changed?
      self.content_type = file.file.content_type
      self.file_size = file.file.size
      if pdf?
        self.number_of_pages = calculate_number_of_pages
      end
    end
  end

  def replace_with!(replacement)
    # NOTE: we're doing this manually because carrierwave is setup such
    # that production instances aren't valid because the storage location
    # for files is not where carrierwave thinks they are (because of
    # virus-checking).
    self.replaced_by = replacement
    cant_be_replaced_by_self
    raise ActiveRecord::RecordInvalid, self if errors.any?

    update_column(:replaced_by_id, replacement.id)
  end

  def uploaded_to_asset_manager!
    update!(uploaded_to_asset_manager_at: Time.zone.now)
    ServiceListeners::AttachmentUpdater.call(attachment_data: self)
  end

  def uploaded_to_asset_manager?
    uploaded_to_asset_manager_at.present?
  end

  def deleted?
    significant_attachment(include_deleted_attachables: true).deleted?
  end

  def draft?
    !significant_attachable.publicly_visible?
  end

  delegate :accessible_to?, to: :significant_attachable

  delegate :access_limited?, to: :last_attachable

  delegate :access_limited_object, to: :last_attachable

  delegate :unpublished?, to: :last_attachable

  delegate :unpublished_edition, to: :last_attachable

  def present_at_unpublish?
    self[:present_at_unpublish]
  end

  def replaced?
    replaced_by.present?
  end

  def visible_to?(user)
    !deleted? && (!draft? || (draft? && accessible_to?(user)))
  end

  def visible_attachment_for(user)
    visible_to?(user) ? significant_attachment : nil
  end

  def visible_attachable_for(user)
    visible_to?(user) ? significant_attachable : nil
  end

  def visible_edition_for(user)
    visible_attachable = visible_attachable_for(user)
    visible_attachable.is_a?(Edition) ? visible_attachable : nil
  end

  def significant_attachable
    significant_attachment.attachable || Attachable::Null.new
  end

  def last_attachable
    last_attachment.attachable || Attachable::Null.new
  end

  def significant_attachment(**args)
    last_publicly_visible_attachment || last_attachment(**args)
  end

  def last_attachment(**args)
    filtered_attachments(**args).last || Attachment::Null.new
  end

  def last_publicly_visible_attachment
    attachments.reverse.detect { |a| (a.attachable || Attachable::Null.new).publicly_visible? }
  end

  def auth_bypass_ids
    attachable && attachable.respond_to?(:auth_bypass_id) ? [attachable.auth_bypass_id] : []
  end

private

  def filtered_attachments(include_deleted_attachables: false)
    if include_deleted_attachables
      attachments
    else
      attachments.select { |attachment| attachment.attachable.present? }
    end
  end

  def cant_be_replaced_by_self
    return if replaced_by.nil?

    errors.add(:base, "can't be replaced by itself") if replaced_by == self
  end

  def handle_to_replace_id
    return if to_replace_id.blank?

    AttachmentData.find(to_replace_id).replace_with!(self)
  end

  def calculate_number_of_pages
    Timeout.timeout(10) do
      PDF::Reader.new(path).page_count
    end
  rescue Timeout::Error, PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError, OpenSSL::Cipher::CipherError
    nil
  end

  def file_is_not_empty
    errors.add(:file, "is an empty file") if file.present? && file.file.zero_size?
  end
end
