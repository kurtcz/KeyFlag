# Homebrew cask for a tap (published copy: kurtcz/homebrew-tap, Casks/keyflag.rb).
# After each release: set version and sha256 (shasum -a 256 build/KeyFlag-<version>.zip).
cask "keyflag" do
  version "0.1.0"
  sha256 "4c2ad5a6c84084bccac1631bf1b68a386ea048c7fc28ff3ca9dcfeecd1adddbc"

  url "https://github.com/kurtcz/KeyFlag/releases/download/v#{version}/KeyFlag-#{version}.zip"
  name "KeyFlag"
  desc "Shows the current keyboard layout's flag next to the pointer"
  homepage "https://github.com/kurtcz/KeyFlag"

  livecheck do
    url "https://raw.githubusercontent.com/kurtcz/KeyFlag/main/appcast.xml"
    strategy :sparkle, &:short_version
  end

  auto_updates true
  depends_on macos: :ventura

  app "KeyFlag.app"

  uninstall quit: "com.tnemec.keyflag"

  zap trash: [
    "~/Library/Caches/com.tnemec.keyflag",
    "~/Library/HTTPStorages/com.tnemec.keyflag",
    "~/Library/Preferences/com.tnemec.keyflag.plist",
  ]
end
