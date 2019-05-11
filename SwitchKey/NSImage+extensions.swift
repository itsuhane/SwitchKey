//
//  NSImage+extensions.swift
//  SwitchKey
//
//  Created by Jinyu Li on 2019/05/10.
//  Copyright © 2019 Jinyu Li. All rights reserved.
//

import Cocoa

extension NSImage {
    // A dumb method:
    //   go over the pixels, and check the color range.
    //   an image can be safely templated if its color range is limited.
    //   luckily, our image is small, and the check is done once for each new icon.
    func canTemplate() -> Bool {
        guard let cgContext = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        
        let nsContext = NSGraphicsContext(cgContext: cgContext, flipped: false)
        NSGraphicsContext.current = nsContext
        draw(in: NSMakeRect(0, 0, size.width, size.height))
        
        guard let pixel = cgContext.data else {
            return false;
        }
        
        let width = cgContext.width;
        var rmin:UInt32 = 255, rmax:UInt32 = 0
        var gmin:UInt32 = 255, gmax:UInt32 = 0
        var bmin:UInt32 = 255, bmax:UInt32 = 0
        for y in 0 ... cgContext.height {
            for x in 0 ... width {
                let px = pixel.load(fromByteOffset: (y * width + x) * 4, as: UInt32.self)
                let r = (px & 0x000000ff) >> 0
                let g = (px & 0x0000ff00) >> 8
                let b = (px & 0x00ff0000) >> 16
                rmin = min(r, rmin)
                rmax = max(r, rmax)
                gmin = min(g, rmin)
                gmax = max(g, rmax)
                bmin = min(b, rmin)
                bmax = max(b, rmax)
            }
        }
        
        NSGraphicsContext.current = nil
        
        let isTemplate = (abs(Int(rmax)-Int(rmin)) + abs(Int(gmax)-Int(gmin)) + abs(Int(bmax)-Int(bmin))) <= 9
        
        return isTemplate
    }
}
