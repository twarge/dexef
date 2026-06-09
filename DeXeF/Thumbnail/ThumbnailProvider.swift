// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation
import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        do {
            let scene = try DXFPreviewDrawing.scene(from: request.fileURL)
            let reply = QLThumbnailReply(contextSize: request.maximumSize, drawing: { context in
                DXFPreviewDrawing.draw(
                    scene: scene,
                    in: CGRect(origin: .zero, size: request.maximumSize),
                    context: context,
                    style: .thumbnail
                )
                return true
            })
            handler(reply, nil)
        } catch {
            handler(nil, error)
        }
    }
}
