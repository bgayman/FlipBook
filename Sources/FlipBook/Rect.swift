//
//  Rect.swift
//  
//
//  Created by Brad Gayman on 1/24/20.
//

#if os(OSX)
import AppKit
public typealias Rect = NSRect

#else
import UIKit
public typealias Rect = CGRect
#endif
