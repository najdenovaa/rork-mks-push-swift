import WidgetKit
import SwiftUI

@main
struct MKSPushWidgetBundle: WidgetBundle {
    var body: some Widget {
        MKSPushInboxWidget()
        MKSPushCompactWidget()
        MKSPushUnreadWidget()
    }
}
