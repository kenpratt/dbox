# Build with: gem build gemspec.rb
Gem::Specification.new do |s|
    s.name = "dropbox-sdk"

    s.version = "1.2"
    s.license = 'MIT'

    s.authors = ["Dropbox, Inc."]
    s.email = ["support-api@dropbox.com"]

    s.add_dependency "json"

    s.homepage = "http://www.dropbox.com/developers/"
    s.summary = "Dropbox REST API Client."
    s.description = <<-EOF
        A library that provides a plain function-call interface to the
        Dropbox API web endpoints.
    EOF

    s.files = [
        "CHANGELOG", "LICENSE", "README",
        "cli_example.rb", "dropbox_controller.rb", "web_file_browser.rb",
        "lib/dropbox_sdk.rb", "data/trusted-certs.crt",
    ]
end
