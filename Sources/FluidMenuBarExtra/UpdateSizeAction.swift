//
//  UpdateSizeAction.swift
//  FluidMenuBarExtra
//
//  Created by Lukas Romsicki on 2022-12-17.
//  Copyright © 2022 Lukas Romsicki.
//

import SwiftUI

struct ContentSize: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        print(#function, " next value: ", nextValue().debugDescription, " existing value: ", value.debugDescription)
        guard nextValue() != .zero else { return }
        value = nextValue()
    }
}
