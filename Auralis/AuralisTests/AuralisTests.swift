//
//  AuralisTests.swift
//  AuralisTests
//
//  Created by Daniel Bell on 10/20/24.
//

import Testing
@testable import Auralis

struct AuralisTests {

    let introSVGString = """
    <svg width="420" height="420" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
    </svg>
    """






    let svgString2 = """
    <svg width="100" height="100" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
      <circle cx="50" cy="50" r="40" fill="blue" />
      <text x="50%" y="50%" dominant-baseline="middle" text-anchor="middle" font-size="20" fill="white">SVG</text>
    </svg>
    """

    let svgString3 = """
    <svg xmlns="http://www.w3.org/2000/svg" width="400" height="400" viewBox="0 0 124 124" fill="none">
    <rect width="124" height="124" rx="24" fill="#F97316"/>
    <path d="M19.375 36.7818V100.625C19.375 102.834 21.1659 104.625 23.375 104.625H87.2181C90.7818 104.625 92.5664 100.316 90.0466 97.7966L26.2034 33.9534C23.6836 31.4336 19.375 33.2182 19.375 36.7818Z" fill="white"/>
    <circle cx="63.2109" cy="37.5391" r="18.1641" fill="black"/>
    <rect opacity="0.4" x="81.1328" y="80.7198" width="17.5687" height="17.3876" rx="4" transform="rotate(-45 81.1328 80.7198)" fill="#FDBA74"/>
    </svg>
    """
    
    @Test func example() async throws {
        let model = SVGViewModel(string: introSVGString)
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}
