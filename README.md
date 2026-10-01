# PR screenshots

Images referenced from BasedHardware/omi#19249 (Omi v2 restyle) and BasedHardware/omi#19252 (iOS Home Screen widgets). Not part of either PR.

- `pr-19249-*.png`: hermetic renders from `app/integration_test/visual_audit` (390x844 pt, sample data, no network images).
- `pr-19252-widgets.png`: the widget SwiftUI views from the widgets branch rendered with `ImageRenderer` on the iOS 18 Simulator (sample data).
- `pr-19252-widgets-v2.png`: the same views after the pendant-photo change (608c062ff8), rendered with the widget's compiled asset catalog so each device shows its own photo.
- `pr-19252-battery-pictures.png`: the Battery widget's picture: the pendant connected, the pendant disconnected (its lights-off photo) and a DevKit disconnected.
- `pr-19252-iphone.png`: the widgets on an iPhone 15 Pro Max, from a build of this branch (cropped).
- `issue-design-delete-swipe-IMG_1277.png`: iPhone screenshot (store build), swiping a Home conversation to delete; cropped to the swipe bar and the confirmation.
- `issue-design-update-prompt-IMG_1281.png`: iPhone screenshot (store build 1.0.552), the update prompt; cropped to the dialog.
