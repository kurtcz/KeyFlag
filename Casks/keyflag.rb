# Homebrew cask for a tap (published copy: kurtcz/homebrew-tap, Casks/keyflag.rb).
# After each release: set version and sha256 (shasum -a 256 build/KeyFlag-<version>.zip).
cask "keyflag" do
  version "0.1.0"
  sha256 "e6bb21feba5aee11de0e60ee2d12a64f7786f15c3d5bc3ae54075f98b6331e00"

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
