import Foundation

/// Fixed OOXML parts shared by every exported package.
enum OfficeTemplates {
    static let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    static let nsA = "http://schemas.openxmlformats.org/drawingml/2006/main"
    static let nsR = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let nsP = "http://schemas.openxmlformats.org/presentationml/2006/main"
    static let nsSheet = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    static let nsPackageRels = "http://schemas.openxmlformats.org/package/2006/relationships"
    static let relType = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    /// Package-level relationships pointing at the main part.
    static func rootRels(target: String) -> String {
        header + "<Relationships xmlns=\"\(nsPackageRels)\"><Relationship Id=\"rId1\" Type=\"\(relType)/officeDocument\" Target=\"\(target)\"/></Relationships>"
    }

    /// `[Content_Types].xml` with the default xml/rels/png types plus one override per part.
    static func contentTypes(overrides: [(part: String, type: String)], png: Bool = false) -> String {
        var xml = header + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        xml += "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        xml += "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        if png { xml += "<Default Extension=\"png\" ContentType=\"image/png\"/>" }
        for o in overrides { xml += "<Override PartName=\"\(o.part)\" ContentType=\"\(o.type)\"/>" }
        return xml + "</Types>"
    }

    /// A relationships part from (id, type suffix, target) triples.
    static func rels(_ items: [(id: String, type: String, target: String)]) -> String {
        header + "<Relationships xmlns=\"\(nsPackageRels)\">"
            + items.map { "<Relationship Id=\"\($0.id)\" Type=\"\(relType)/\($0.type)\" Target=\"\($0.target)\"/>" }.joined()
            + "</Relationships>"
    }

    static let emptyGroup = "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>"
        + "<p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"

    static let styles = header + "<styleSheet xmlns=\"\(nsSheet)\">"
        + "<fonts count=\"1\"><font><sz val=\"11\"/><name val=\"Calibri\"/><family val=\"2\"/></font></fonts>"
        + "<fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills>"
        + "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>"
        + "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
        + "<cellXfs count=\"5\">"
        + "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>"
        + [9, 10, 3, 4].map { "<xf numFmtId=\"\($0)\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\"/>" }.joined()
        + "</cellXfs>"
        + "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>"
        + "</styleSheet>"

    static let slideMaster = header
        + "<p:sldMaster xmlns:a=\"\(nsA)\" xmlns:r=\"\(nsR)\" xmlns:p=\"\(nsP)\">"
        + "<p:cSld><p:bg><p:bgRef idx=\"1001\"><a:schemeClr val=\"bg1\"/></p:bgRef></p:bg>"
        + "<p:spTree>\(emptyGroup)</p:spTree></p:cSld>"
        + "<p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" "
        + "accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/>"
        + "<p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rId1\"/></p:sldLayoutIdLst>"
        + "<p:txStyles>"
        + "<p:titleStyle><a:lvl1pPr><a:defRPr sz=\"4400\"/></a:lvl1pPr></p:titleStyle>"
        + "<p:bodyStyle><a:lvl1pPr><a:defRPr sz=\"1800\"/></a:lvl1pPr></p:bodyStyle>"
        + "<p:otherStyle><a:lvl1pPr><a:defRPr sz=\"1800\"/></a:lvl1pPr></p:otherStyle>"
        + "</p:txStyles></p:sldMaster>"

    static let slideLayout = header
        + "<p:sldLayout xmlns:a=\"\(nsA)\" xmlns:r=\"\(nsR)\" xmlns:p=\"\(nsP)\" type=\"blank\" preserve=\"1\">"
        + "<p:cSld name=\"Blank\"><p:spTree>\(emptyGroup)</p:spTree></p:cSld>"
        + "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>"

    static let theme: String = {
        func color(_ tag: String, _ hex: String) -> String { "<a:\(tag)><a:srgbClr val=\"\(hex)\"/></a:\(tag)>" }
        let fonts = "<a:latin typeface=\"Helvetica\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/>"
        let fill = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        let line = [6350, 12700, 19050].map { "<a:ln w=\"\($0)\" cap=\"flat\" cmpd=\"sng\" algn=\"ctr\">\(fill)<a:prstDash val=\"solid\"/></a:ln>" }.joined()
        let effect = String(repeating: "<a:effectStyle><a:effectLst/></a:effectStyle>", count: 3)
        return header + "<a:theme xmlns:a=\"\(nsA)\" name=\"PDF Yaho\"><a:themeElements>"
            + "<a:clrScheme name=\"PDF Yaho\">"
            + "<a:dk1><a:sysClr val=\"windowText\" lastClr=\"000000\"/></a:dk1><a:lt1><a:sysClr val=\"window\" lastClr=\"FFFFFF\"/></a:lt1>"
            + color("dk2", "44546A") + color("lt2", "E7E6E6") + color("accent1", "4472C4") + color("accent2", "ED7D31")
            + color("accent3", "A5A5A5") + color("accent4", "FFC000") + color("accent5", "5B9BD5") + color("accent6", "70AD47")
            + color("hlink", "0563C1") + color("folHlink", "954F72")
            + "</a:clrScheme>"
            + "<a:fontScheme name=\"PDF Yaho\"><a:majorFont>\(fonts)</a:majorFont><a:minorFont>\(fonts)</a:minorFont></a:fontScheme>"
            + "<a:fmtScheme name=\"PDF Yaho\">"
            + "<a:fillStyleLst>\(fill)\(fill)\(fill)</a:fillStyleLst>"
            + "<a:lnStyleLst>\(line)</a:lnStyleLst>"
            + "<a:effectStyleLst>\(effect)</a:effectStyleLst>"
            + "<a:bgFillStyleLst>\(fill)\(fill)\(fill)</a:bgFillStyleLst>"
            + "</a:fmtScheme></a:themeElements></a:theme>"
    }()
}
