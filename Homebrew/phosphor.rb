cask "phosphor" do
  version "1.0.6"
  sha256 "0e5c6d4bfb551ff91584ec142c0b19541e8a34e82db0a3784d170bec4d824b6a"

  url "https://github.com/momenbasel/Phosphor/releases/download/v#{version}/Phosphor.dmg"
  name "Phosphor"
  desc "Free and open-source iOS device manager for macOS"
  homepage "https://github.com/momenbasel/Phosphor"

  depends_on macos: ">= :sonoma"
  depends_on formula: "libimobiledevice"

  app "Phosphor.app"

  zap trash: [
    "~/Library/Caches/com.phosphor.app",
    "~/Library/Preferences/com.phosphor.app.plist",
  ]
end
