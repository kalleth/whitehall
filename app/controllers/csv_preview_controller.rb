class CsvPreviewController < ApplicationController
  slimmer_template "chromeless"

  def show
    respond_to do |format|
      format.html do
        @csv_response = CsvFileFromPublicHost.csv_response(attachment_data.file.asset_manager_path)

        if attachment_data.csv? && attachment_visible? && attachment.attachable.draft?
          expires_headers
          @edition = attachment.attachable
          @csv_preview = CsvFileFromPublicHost.csv_preview_from(@csv_response)
          @page_base_href = Plek.new.website_root
          render layout: "draft_html_attachments"
        elsif attachment_data.csv? && attachment_visible? && visible_edition
          expires_headers
          @edition = visible_edition
          @csv_preview = CsvFileFromPublicHost.csv_preview_from(@csv_response)
          @page_base_href = Plek.new.website_root
          render layout: "html_attachments"
        else
          fail
        end
      end
    end
  end

private

  def fail
    if attachment_data.unpublished?
      redirect_url = attachment_data.unpublished_edition.unpublishing.document_path
      redirect_to redirect_url
    elsif attachment_data.replaced?
      expires_headers
      redirect_to attachment_data.replaced_by.url, status: :moved_permanently, allow_other_host: true
    elsif incoming_upload_exists?
      redirect_to_placeholder
    else
      render plain: "Not found", status: :not_found
    end
  end

  def attachment_visible?
    upload_exists? && attachment_data.visible_to?(current_user)
  end

  def visible_edition
    @visible_edition ||= attachment_data.visible_edition_for(current_user)
  end

  def incoming_upload_exists?
    (@csv_response.status == 302) && redirect_path_matches_placeholder_path
  end

  def redirect_path_matches_placeholder_path
    URI.parse(@csv_response.headers["Location"]).path == placeholder_path
  end

  def upload_exists?
    @csv_response.status == 206
  end

  def attachment_data
    @attachment_data ||= attachment.attachment_data
  end

  def attachment
    @attachment ||= Attachment.find(params[:id])
  end

  def expires_headers
    if current_user.nil?
      expires_in(Whitehall.uploads_cache_max_age, public: true)
    else
      expires_now
    end
  end

  def redirect_to_placeholder
    # Cache is explicitly 1 minute to prevent the virus redirect beng
    # cached by CDNs.
    expires_in(1.minute, public: true)
    redirect_to placeholder_path
  end
end
