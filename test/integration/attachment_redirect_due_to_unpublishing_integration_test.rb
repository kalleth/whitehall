require "test_helper"
require "capybara/rails"

class AttachmentRedirectDueToUnpublishingIntegrationTest < ActionDispatch::IntegrationTest
  extend Minitest::Spec::DSL
  include Capybara::DSL
  include Rails.application.routes.url_helpers
  include TaxonomyHelper

  describe "attachment redirect due to unpublishing" do
    let(:filename) { "sample.docx" }
    let(:file) { File.open(path_to_attachment(filename)) }
    let(:attachment) { build(:file_attachment, attachable: attachable, file: file) }
    let(:attachable) { edition }
    let(:asset_id) { "asset-id" }
    let(:redirect_path) { Whitehall.url_maker.public_document_path(edition) }
    let(:redirect_url) { Whitehall.url_maker.public_document_url(edition) }
    let(:topic_taxon) { build(:taxon_hash) }

    before do
      stub_publishing_api_has_linkables([], document_type: "topic")
      login_as create(:managing_editor)
      setup_publishing_api_for(edition)
      attachable.attachments << attachment
      stub_whitehall_asset(filename, id: asset_id)
      attachable.save!
    end

    context "given a published document with file attachment" do
      let(:edition) { create(:published_news_article) }

      it "sets redirect URL for attachment in Asset Manager when document is unpublished" do
        stub_publishing_api_expanded_links_with_taxons(edition.content_id, [])

        visit admin_news_article_path(edition)
        unpublish_document_published_in_error
        assert_sets_redirect_url_in_asset_manager_to redirect_url
      end

      it "sets redirect URL for attachment in Asset Manager when document is consolidated" do
        stub_publishing_api_expanded_links_with_taxons(edition.content_id, [])

        visit admin_news_article_path(edition)
        consolidate_document
        assert_sets_redirect_url_in_asset_manager_to redirect_url
      end

      it "does not set a redirect URI for attachment in Asset Manager when document is withdrawn" do
        stub_publishing_api_expanded_links_with_taxons(edition.content_id, [])

        visit admin_news_article_path(edition)
        withdraw_document
        refute_sets_redirect_url_in_asset_manager
      end

      it "does not redirect new attachments added after a document is unpublished" do
        stub_publishing_api_expanded_links_with_taxons(edition.content_id, [])

        visit admin_news_article_path(edition)
        unpublish_document_published_in_error

        file = File.open(path_to_attachment("sample.csv"))
        new_attachment = build(:file_attachment, attachable: attachable, file: file)
        attachable.attachments << new_attachment
        new_attachment.save!

        refute_sets_redirect_url_in_asset_manager
      end
    end

    context "given a published document with HTML attachment" do
      let(:edition) { create(:published_publication, :with_html_attachment) }

      it "unpublishes the HTML attachment when the document is unpublished" do
        stub_publishing_api_expanded_links_with_taxons(edition.content_id, [])

        visit admin_publication_path(edition)
        assert_redirected_in_publishing_api(edition.html_attachments.first.content_id, redirect_path)

        unpublish_document_published_in_error
      end

      it "sets redirect URL for attachment in Asset Manager when document is consolidated" do
        stub_publishing_api_expanded_links_with_taxons(edition.content_id, [])

        visit admin_publication_path(edition)
        consolidate_document
        assert_sets_redirect_url_in_asset_manager_to redirect_url
      end

      it "does not set a redirect URI for attachment in Asset Manager when document is withdrawn" do
        stub_publishing_api_expanded_links_with_taxons(edition.content_id, [])

        visit admin_publication_path(edition)
        withdraw_document
        refute_sets_redirect_url_in_asset_manager
      end

      it "does not redirect new attachments added after a document is unpublished" do
        stub_publishing_api_expanded_links_with_taxons(edition.content_id, [])

        visit admin_publication_path(edition)
        unpublish_document_published_in_error

        file = File.open(path_to_attachment("sample.csv"))
        new_attachment = build(:file_attachment, attachable: attachable, file: file)
        attachable.attachments << new_attachment
        new_attachment.save!

        refute_sets_redirect_url_in_asset_manager
      end
    end

    context "given a published consultation with outcome with file attachment" do
      let(:edition) { create(:published_consultation) }
      let(:outcome_attributes) { attributes_for(:consultation_outcome) }
      let(:attachable) { edition.create_outcome!(outcome_attributes) }

      it "sets redirect URL for attachment in Asset Manager when document is unpublished" do
        stub_publishing_api_expanded_links_with_taxons(edition.content_id, [])

        visit admin_consultation_path(edition)
        unpublish_document_published_in_error
        assert_sets_redirect_url_in_asset_manager_to redirect_url
      end

      it "does not set redirect URI for attachment in Asset Manager when document is withdrawn" do
        stub_publishing_api_expanded_links_with_taxons(edition.content_id, [])

        visit admin_consultation_path(edition)
        withdraw_document
        refute_sets_redirect_url_in_asset_manager
      end
    end

    context "given a published consultation with feedback with file attachment" do
      let(:edition) { create(:published_consultation) }
      let(:feedback_attributes) { attributes_for(:consultation_public_feedback) }
      let(:attachable) { edition.create_public_feedback!(feedback_attributes) }

      it "sets redirect URL for attachment in Asset Manager when document is unpublished" do
        stub_publishing_api_expanded_links_with_taxons(edition.content_id, [])

        visit admin_consultation_path(edition)
        unpublish_document_published_in_error
        assert_sets_redirect_url_in_asset_manager_to redirect_url
      end

      it "does not set redirect URI for attachment in Asset Manager when document is withdrawn" do
        stub_publishing_api_expanded_links_with_taxons(edition.content_id, [])

        visit admin_consultation_path(edition)
        withdraw_document
        refute_sets_redirect_url_in_asset_manager
      end
    end

    context "given an unpublished document with file attachment" do
      let(:edition) { create(:news_article, :unpublished) }

      it "resets redirect URI for attachment in Asset Manager when document is published" do
        stub_publishing_api_expanded_links_with_taxons(edition.content_id, [])
        stub_publishing_api_links_with_taxons(edition.content_id, [topic_taxon["content_id"]])

        visit admin_news_article_path(edition)
        force_publish_document
        assert_sets_redirect_url_in_asset_manager_to nil
      end
    end

    context "given an unpublished consultation with outcome with file attachment" do
      let(:edition) { create(:consultation, :unpublished) }
      let(:outcome_attributes) { attributes_for(:consultation_outcome) }
      let(:attachable) { edition.create_outcome!(outcome_attributes) }

      it "resets redirect URI for attachment in Asset Manager when document is published" do
        stub_publishing_api_expanded_links_with_taxons(edition.content_id, [])
        stub_publishing_api_links_with_taxons(edition.content_id, [topic_taxon["content_id"]])

        visit admin_consultation_path(edition)
        force_publish_document
        assert_sets_redirect_url_in_asset_manager_to nil
      end
    end

    context "given a withdrawn document with file attachment" do
      let(:edition) { create(:news_article, :published, :withdrawn) }

      it "resets redirect URI for attachment in Asset Manager when document is unwithdrawn" do
        stub_publishing_api_expanded_links_with_taxons(edition.content_id, [])

        visit admin_news_article_path(edition)
        unwithdraw_document
        assert_sets_redirect_url_in_asset_manager_to nil
      end
    end

    context "given a withdrawn consultation with outcome with file attachment" do
      let(:edition) { create(:consultation, :published, :withdrawn) }
      let(:outcome_attributes) { attributes_for(:consultation_outcome) }
      let(:attachable) { edition.create_outcome!(outcome_attributes) }

      it "resets redirect URI for attachment in Asset Manager when document is unwithdrawn" do
        stub_publishing_api_expanded_links_with_taxons(edition.content_id, [])

        visit admin_consultation_path(edition)
        unwithdraw_document
        assert_sets_redirect_url_in_asset_manager_to nil
      end
    end

  private

    def ends_with(expected)
      ->(actual) { actual.end_with?(expected) }
    end

    def setup_publishing_api_for(edition)
      stub_publishing_api_has_links({ content_id: edition.document.content_id, links: {} })
    end

    def path_to_attachment(filename)
      fixture_path.join(filename)
    end

    def stub_whitehall_asset(filename, attributes = {})
      url_id = "http://asset-manager/assets/#{attributes[:id]}"
      Services.asset_manager.stubs(:whitehall_asset)
        .with(&ends_with(filename))
        .returns(attributes.merge(id: url_id).stringify_keys)
    end

    def assert_sets_redirect_url_in_asset_manager_to(redirect_url)
      Services.asset_manager.expects(:update_asset)
        .with(asset_id, "redirect_url" => redirect_url)
        .at_least_once
      AssetManagerAttachmentRedirectUrlUpdateWorker.drain
    end

    def assert_redirected_in_publishing_api(content_id, redirect_path)
      Services.publishing_api.expects(:unpublish)
        .with(
          content_id,
          type: "redirect",
          alternative_path: redirect_path,
          locale: "en",
          allow_draft: false,
          discard_drafts: true,
        )
        .once
    end

    def refute_sets_redirect_url_in_asset_manager
      Services.asset_manager.expects(:update_asset)
        .with(asset_id, "redirect_url" => anything)
        .never
      AssetManagerAttachmentRedirectUrlUpdateWorker.drain
    end

    def unpublish_document_published_in_error
      click_link "Withdraw or unpublish"
      within "#js-published-in-error-form" do
        click_button "Unpublish"
      end
      assert_text "This document has been unpublished"
    end

    def consolidate_document
      click_link "Withdraw or unpublish"
      within "#js-consolidated-form" do
        fill_in "consolidated_alternative_url", with: "https://www.test.gov.uk/example"
        click_button "Unpublish"
      end
      assert_text "This document has been unpublished"
    end

    def withdraw_document
      click_link "Withdraw or unpublish"
      within "#js-withdraw-form" do
        fill_in "withdrawal_explanation", with: "testing"
        click_button "Withdraw"
      end
      assert_text "This document has been marked as withdrawn"
    end

    def force_publish_document
      click_link "Force publish"
      fill_in "Reason for force publishing", with: "testing"
      click_button "Force publish"
      assert_text %r{The document .* has been published}
    end

    def unwithdraw_document
      click_link "Unwithdraw"
      click_button "Unwithdraw"
      assert_text "This document has been unwithdrawn"
    end
  end
end
