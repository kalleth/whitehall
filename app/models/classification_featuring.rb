class ClassificationFeaturing < ApplicationRecord
  belongs_to :edition, inverse_of: :classification_featurings
  belongs_to :offsite_link
  belongs_to :classification, inverse_of: :classification_featurings
  belongs_to :image, class_name: "ClassificationFeaturingImageData", foreign_key: :classification_featuring_image_data_id

  accepts_nested_attributes_for :image, reject_if: :all_blank

  validates :image, presence: true
  validates :alt_text, presence: true, allow_blank: true
  validates :alt_text, length: { maximum: 255 }

  validates :classification, :ordering, presence: true

  validates :edition_id, uniqueness: { scope: :classification_id }, unless: :offsite?

  after_save :republish_classification_to_publishing_api
  after_destroy :republish_classification_to_publishing_api

  def title
    if offsite?
      offsite_link.title
    else
      edition.title
    end
  end

  def summary
    if offsite?
      offsite_link.summary
    else
      edition.summary
    end
  end

  def url
    if offsite?
      offsite_link.url
    else
      Whitehall.url_maker.public_document_path(edition)
    end
  end

  def offsite?
    edition.nil?
  end

  def republish_classification_to_publishing_api
    Whitehall::PublishingApi.republish_async(classification)
  end
end
