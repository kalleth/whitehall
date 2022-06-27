# On the CI box we have seen intermittent failures.
# We think this may be due to timeouts (the default is 2 secs),
# so we've increased the default timeout.
Capybara.default_max_wait_time = 5

Capybara.register_driver :whitehall_headless_chrome do |app|
  client = Selenium::WebDriver::Remote::Http::Default.new(read_timeout: 300)
  Capybara::Selenium::Driver.new(app,
                                 browser: :chrome,
                                 http_client: client,
                                 capabilities: GovukTest.headless_chrome_selenium_options)
end

Capybara.javascript_driver = :whitehall_headless_chrome
module ScreenshotHelper
  def screenshot(name = "capybara")
    page.driver.render(Rails.root.join("tmp/#{name}.png"), full: true)
  end
end

World(ScreenshotHelper)
