# Homebrew cask. This repository doubles as a tap:
#   brew tap saissaken/dotwell https://github.com/Saissaken/dotwell
#   brew install --cask dotwell
cask "dotwell" do
  # The app updates itself with Sparkle, so the cask always installs the newest release.
  version :latest
  sha256 :no_check

  url "https://github.com/Saissaken/dotwell/releases/latest/download/Dotwell.dmg"
  name "Dotwell"
  desc "Tiny menu bar monitor for ping, CPU, memory, disk, power and network"
  homepage "https://saissaken.github.io/dotwell/"

  auto_updates true
  depends_on macos: ">= :ventura"

  app "Dotwell.app"

  uninstall quit: "com.saissaken.Dotwell"

  zap trash: [
    "~/Library/Caches/com.saissaken.Dotwell",
    "~/Library/HTTPStorages/com.saissaken.Dotwell",
    "~/Library/Preferences/com.saissaken.Dotwell.plist",
  ]

  caveats <<~EOS
    Dotwell is not notarized yet. Allow the first launch once in
    System Settings > Privacy & Security > Open Anyway.
  EOS
end
