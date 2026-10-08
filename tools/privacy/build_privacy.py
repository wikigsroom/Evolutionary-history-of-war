"""Build one verified privacy-policy source into a template-based DOCX and static site."""
from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import zipfile

from lxml import etree
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "output/privacy-policy/2026-10-08"
DOCS = ROOT / "docs/privacy-policy"
SITE = ROOT / "web/privacy-policy"
TEMPLATE = WORK / "source/privacy-policy-template.docx"
EXPECTED_TEMPLATE_SHA = "662473e9abc64942e91a57dfeca7248c53883468805a658405b5c5af8e790a20"
W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
NS = {"w": W}
SERVICE_LINKS = {
    "https://vercel.com/legal/privacy-notice": "Vercel 隐私说明",
    "https://www.microsoft.com/zh-cn/privacy/privacystatement": "微软隐私声明",
}


def q(name: str) -> str:
    return f"{{{W}}}{name}"


def set_prop(parent: etree._Element, name: str, **attrs: str) -> etree._Element:
    element = parent.find(q(name))
    if element is None:
        element = etree.SubElement(parent, q(name))
    for key, value in attrs.items():
        element.set(q(key), str(value))
    return element


def load_source() -> tuple[dict, dict]:
    identity = json.loads((WORK / "source/identity.json").read_text(encoding="utf-8"))
    if not identity.get("operator_name") or not identity.get("privacy_email"):
        raise SystemExit("Publication blocked: actual operator name and privacy contact email are required.")
    if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", identity["privacy_email"]):
        raise SystemExit("Publication blocked: invalid privacy contact email.")
    if identity.get("operator_type") == "company" and not identity.get("registered_address"):
        raise SystemExit("Publication blocked: company address is required.")
    source = json.loads((WORK / "source/policy.json").read_text(encoding="utf-8"))

    def replace(value):
        if isinstance(value, str):
            for key in ("operator_name", "privacy_email"):
                value = value.replace("{" + key + "}", identity[key])
            return value
        if isinstance(value, list):
            return [replace(item) for item in value]
        if isinstance(value, dict):
            return {key: replace(item) for key, item in value.items()}
        return value

    source = replace(source)
    if identity.get("registered_address"):
        source["sections"][-1]["blocks"].insert(1, {
            "type": "paragraph", "text": "注册地址：" + identity["registered_address"] + "。"
        })
    serialized = json.dumps(source, ensure_ascii=False)
    for forbidden in ("{operator_name}", "{privacy_email}", "像素指挥台", "【运营", "【游戏", "【数据", "待确认"):
        if forbidden in serialized:
            raise SystemExit(f"Publication blocked: unresolved or obsolete text {forbidden!r}.")
    return source, identity


def build_docx(source: dict, identity: dict) -> Path:
    if hashlib.sha256(TEMPLATE.read_bytes()).hexdigest() != EXPECTED_TEMPLATE_SHA:
        raise SystemExit("Reference template hash changed; stop before authoring.")
    with zipfile.ZipFile(TEMPLATE) as package:
        xml = etree.fromstring(package.read("word/document.xml"))
        original_paras = xml.xpath(".//w:p", namespaces=NS)
        table_patterns = xml.xpath(".//w:tbl", namespaces=NS)
        body = xml.find(q("body"))
        section = deepcopy(body.find(q("sectPr")))

        def paragraph(text: str, role: str = "body", *, page_break=False):
            index = {"body": 17, "notice": 2, "notice_title": 0, "title": 15,
                     "meta": 12, "chapter": 34, "subheading": 37}.get(role, 17)
            reference = original_paras[index]
            p = etree.Element(q("p"))
            props = deepcopy(reference.find(q("pPr")))
            if props is None:
                props = etree.Element(q("pPr"))
            for unwanted in ("numPr", "pBdr", "sectPr"):
                for el in props.findall(q(unwanted)):
                    props.remove(el)
            set_prop(props, "widowControl", val="1")
            set_prop(props, "snapToGrid", val="0")
            if role in ("title", "chapter", "subheading", "notice_title"):
                set_prop(props, "keepNext", val="1")
            if role == "title":
                existing = props.find(q("pStyle"))
                if existing is not None:
                    props.remove(existing)
                ps = etree.Element(q("pStyle"))
                ps.set(q("val"), "Title")
                props.insert(0, ps)
            if page_break:
                set_prop(props, "pageBreakBefore", val="1")
            p.append(props)
            run = etree.SubElement(p, q("r"))
            rp = deepcopy(reference.find("w:r/w:rPr", NS))
            if rp is None:
                rp = etree.Element(q("rPr"))
            set_prop(rp, "color", val="000000")
            for bad in ("u", "highlight"):
                for el in rp.findall(q(bad)):
                    rp.remove(el)
            run.append(rp)
            node = etree.SubElement(run, q("t"))
            node.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")
            node.text = text
            return p

        def table(block: dict, pattern_index: int):
            ref = table_patterns[pattern_index]
            table = etree.Element(q("tbl"))
            props = deepcopy(ref.find(q("tblPr")))
            set_prop(props, "tblW", w="8306", type="dxa")
            set_prop(props, "tblInd", w="0", type="dxa")
            set_prop(props, "tblLayout", type="fixed")
            table.append(props)
            widths = [1350, 2500, 2900, 1556] if pattern_index == 0 else [1300, 1350, 3650, 2006]
            grid = etree.SubElement(table, q("tblGrid"))
            for width in widths:
                col = etree.SubElement(grid, q("gridCol"))
                col.set(q("w"), str(width))
            reference_rows = ref.findall(q("tr"))
            rows = [block["headers"]] + block["rows"]
            for row_number, values in enumerate(rows):
                row = etree.SubElement(table, q("tr"))
                rprops = etree.SubElement(row, q("trPr"))
                set_prop(rprops, "cantSplit")
                if row_number == 0:
                    set_prop(rprops, "tblHeader")
                ref_cells = reference_rows[0 if row_number == 0 else 1].findall(q("tc"))
                for col_number, text in enumerate(values):
                    cell = etree.SubElement(row, q("tc"))
                    cp = deepcopy(ref_cells[col_number].find(q("tcPr")))
                    if cp is None:
                        cp = etree.Element(q("tcPr"))
                    set_prop(cp, "tcW", w=str(widths[col_number]), type="dxa")
                    cell.append(cp)
                    p = deepcopy(ref_cells[col_number].find(q("p")))
                    for el in list(p):
                        if el.tag != q("pPr"):
                            p.remove(el)
                    pp = p.find(q("pPr"))
                    if pp is None:
                        pp = etree.SubElement(p, q("pPr"))
                    set_prop(pp, "spacing", before="90", after="90", line="260", lineRule="auto")
                    set_prop(pp, "jc", val="left" if row_number else "center")
                    set_prop(pp, "widowControl", val="1")
                    if row_number < len(rows) - 1:
                        set_prop(pp, "keepNext", val="1")
                    run = etree.SubElement(p, q("r"))
                    rp = etree.SubElement(run, q("rPr"))
                    set_prop(rp, "rFonts", ascii="Times New Roman", hAnsi="Times New Roman", eastAsia="华文仿宋")
                    set_prop(rp, "sz", val="20")
                    set_prop(rp, "szCs", val="20")
                    set_prop(rp, "color", val="000000")
                    if row_number == 0:
                        set_prop(rp, "b")
                    if text in SERVICE_LINKS:
                        text = SERVICE_LINKS[text] + "\n链接见本节正文"
                    for line_index, line in enumerate(text.splitlines()):
                        if line_index:
                            etree.SubElement(run, q("br"))
                        etree.SubElement(run, q("t")).text = line
                    cell.append(p)
            return table

        for element in list(body):
            body.remove(element)
        body.append(paragraph("隐私保护提示", "notice_title"))
        for text in source["notice"]:
            body.append(paragraph(text, "notice"))
        body.append(paragraph("更新日期：" + source["updated"], "meta", page_break=True))
        body.append(paragraph("生效日期：" + source["effective"], "meta"))
        body.append(paragraph("政策版本：" + source["policy_version"], "meta"))
        body.append(paragraph("纪元急袭隐私政策", "title"))
        for text in source["intro"]:
            body.append(paragraph(text))
        body.append(paragraph("政策目录", "subheading", page_break=True))
        labels = list("一二三四五六七八九") + ["十"]
        for label, sec in zip(labels, source["sections"]):
            body.append(paragraph(label + " " + sec["title"]))
        for section_number, (label, sec) in enumerate(zip(labels, source["sections"])):
            body.append(paragraph(label + " " + sec["title"], "chapter"))
            for block in sec["blocks"]:
                if block["type"].endswith("table"):
                    body.append(table(block, 0 if block["type"] == "data_table" else 1))
                    if block["type"] == "service_table":
                        for row in block["rows"]:
                            if row[-1] in SERVICE_LINKS:
                                body.append(paragraph(SERVICE_LINKS[row[-1]] + "：" + row[-1]))
                else:
                    body.append(paragraph(block["text"], "subheading" if block["type"] == "heading" else "body"))
        body.append(section)

        styles = etree.fromstring(package.read("word/styles.xml"))
        title = etree.SubElement(styles, q("style"))
        title.set(q("type"), "paragraph")
        title.set(q("styleId"), "Title")
        title.set(q("customStyle"), "1")
        set_prop(title, "name", val="Title")
        set_prop(title, "basedOn", val="1")
        set_prop(title, "qFormat")
        pp = etree.SubElement(title, q("pPr"))
        set_prop(pp, "keepNext")
        set_prop(pp, "jc", val="center")
        rp = etree.SubElement(title, q("rPr"))
        set_prop(rp, "rFonts", ascii="Times New Roman", hAnsi="Times New Roman", eastAsia="华文仿宋")
        set_prop(rp, "sz", val="32")
        set_prop(rp, "color", val="000000")
        set_prop(rp, "b")

        core = etree.fromstring(package.read("docProps/core.xml"))
        dc = "http://purl.org/dc/elements/1.1/"
        cp = "http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
        dct = "http://purl.org/dc/terms/"
        values = {"{" + dc + "}title": "纪元急袭隐私政策", "{" + dc + "}subject": source["policy_version"],
                  "{" + dc + "}creator": identity["operator_name"], "{" + cp + "}lastModifiedBy": identity["operator_name"]}
        for name, text in values.items():
            el = core.find(name)
            if el is None:
                el = etree.SubElement(core, name)
            el.text = text
        timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
        for date_key in ("created", "modified"):
            date_element = core.find("{" + dct + "}" + date_key)
            if date_element is not None:
                date_element.text = timestamp
        revision = core.find("{" + cp + "}revision")
        if revision is not None:
            revision.text = "1"
        app = etree.fromstring(package.read("docProps/app.xml"))
        for el in list(app):
            if etree.QName(el).localname in ("Pages", "Words", "Characters", "CharactersWithSpaces", "Lines", "Paragraphs", "TotalTime"):
                app.remove(el)
        serialize = lambda el: etree.tostring(el, encoding="UTF-8", xml_declaration=True, standalone=True)
        replacements = {"word/document.xml": serialize(xml), "word/styles.xml": serialize(styles),
                        "docProps/core.xml": serialize(core), "docProps/app.xml": serialize(app)}
        output = DOCS / "纪元急袭隐私政策.docx"
        output.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(output, "w") as result:
            for entry in package.infolist():
                result.writestr(deepcopy(entry), replacements.get(entry.filename, package.read(entry)))
        fidelity = []
        with zipfile.ZipFile(output) as result:
            for entry in package.infolist():
                same = package.read(entry) == result.read(entry.filename)
                fidelity.append({"part": entry.filename, "changed": not same, "allowed": entry.filename in replacements})
                if not same and entry.filename not in replacements:
                    raise RuntimeError("Unexpected package mutation: " + entry.filename)
        (WORK / "qa").mkdir(parents=True, exist_ok=True)
        (WORK / "qa/package-fidelity.json").write_text(json.dumps(fidelity, indent=2), encoding="utf-8")
        return output


def build_markdown(source: dict) -> str:
    out = ["# 纪元急袭隐私政策", "", "更新日期：" + source["updated"],
           "生效日期：" + source["effective"], "政策版本：" + source["policy_version"], "", "## 隐私保护提示", ""]
    for text in source["notice"]:
        out.extend([text, ""])
    out.extend(["## 适用范围与运营者", ""])
    for text in source["intro"]:
        out.extend([text, ""])
    for number, sec in enumerate(source["sections"], 1):
        out.extend([f"## {number} {sec['title']}", ""])
        for block in sec["blocks"]:
            if block["type"].endswith("table"):
                out.append("| " + " | ".join(block["headers"]) + " |")
                out.append("| " + " | ".join(["---"] * len(block["headers"])) + " |")
                for row in block["rows"]:
                    out.append("| " + " | ".join(row) + " |")
                out.append("")
            else:
                out.extend([("### " if block["type"] == "heading" else "") + block["text"], ""])
    return "\n".join(out)


def linked(text: str, email: str) -> str:
    escaped = html.escape(text)
    escaped = escaped.replace(html.escape(email), f'<a href="mailto:{html.escape(email, quote=True)}">{html.escape(email)}</a>')
    for url, label in SERVICE_LINKS.items():
        escaped = escaped.replace(url, f'<a href="{url}" rel="noopener noreferrer">{label}</a>')
    return escaped


def build_site(source: dict, identity: dict, docx: Path):
    SITE.mkdir(parents=True, exist_ok=True)
    (SITE / "assets").mkdir(exist_ok=True)
    email = identity["privacy_email"]
    nav = "".join(f'<a href="#{s["id"]}"><span>{i:02}</span>{html.escape(s["title"])}</a>' for i, s in enumerate(source["sections"], 1))
    sections = []
    for number, sec in enumerate(source["sections"], 1):
        blocks = []
        for block in sec["blocks"]:
            if block["type"].endswith("table"):
                heads = "".join('<th scope="col">' + html.escape(h) + "</th>" for h in block["headers"])
                rows = "".join("<tr>" + "".join("<td>" + linked(v, email) + "</td>" for v in row) + "</tr>" for row in block["rows"])
                blocks.append(f'<div class="table-scroll" role="region" aria-label="{html.escape(sec["title"],quote=True)} 信息表" tabindex="0"><table><thead><tr>{heads}</tr></thead><tbody>{rows}</tbody></table></div>')
            else:
                tag = "h3" if block["type"] == "heading" else "p"
                blocks.append(f"<{tag}>{linked(block['text'],email)}</{tag}>")
        sections.append(f'<section id="{sec["id"]}" aria-labelledby="title-{sec["id"]}"><h2 id="title-{sec["id"]}"><span>{number:02}</span>{html.escape(sec["title"])}</h2>{"".join(blocks)}</section>')
    notices = "".join("<li>" + linked(text, email) + "</li>" for text in source["notice"][1:])
    intro = "".join("<p>" + linked(text, email) + "</p>" for text in source["intro"])
    page = f'''<!doctype html>
<html lang="zh-CN">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>纪元急袭隐私政策</title><meta name="description" content="纪元急袭 Windows 与 Android 原生游戏的隐私政策：本机存档、权限、联系信息、网站托管与个人信息权利。">
<meta name="color-scheme" content="light"><meta name="referrer" content="no-referrer">
<link rel="icon" type="image/png" href="/assets/knight.png"><link rel="stylesheet" href="/styles.css"></head>
<body><a class="skip-link" href="#policy">跳到隐私条款正文</a>
<header class="site-header"><a class="brand" href="#top"><img src="/assets/knight.png" alt="纪元急袭骑士标志" width="52" height="52"><span>纪元急袭<small>Epoch Rush</small></span></a><a class="header-contact" href="mailto:{html.escape(email,quote=True)}">联系开发者 <span aria-hidden="true">↗</span></a></header>
<main id="top"><div class="masthead"><div class="eyebrow">游戏与玩家信息保护</div><h1>隐私政策</h1><p class="lead">了解本机数据如何保存，以及您可以如何管理自己的信息。</p><div class="metadata"><span>更新 {source['updated']}</span><span>生效 {source['effective']}</span><span>适用 Godot {source['game_version']} · Windows / Android</span></div><div class="downloads"><a href="/privacy-policy.docx" download>下载 Word 正文 <span aria-hidden="true">↓</span></a><a href="/privacy-policy.md" download>保存 Markdown 正文 <span aria-hidden="true">↓</span></a></div></div>
<div class="reading-layout"><aside class="desktop-nav" aria-label="政策章节"><p class="nav-title">条款目录</p><nav>{nav}</nav><p class="nav-version">{source['policy_version']}</p></aside>
<article id="policy"><details class="mobile-nav"><summary>查看十项条款目录</summary><nav aria-label="手机条款目录">{nav}</nav></details>
<section class="notice" aria-labelledby="notice-title"><div class="notice-heading"><img src="/assets/knight.png" alt="" width="62" height="62"><div><p class="eyebrow">阅读提示</p><h2 id="notice-title">当前版本，数据以本机保存为主</h2></div></div><p>{linked(source['notice'][0],email)}</p><ul>{notices}</ul></section>
<section class="scope" aria-labelledby="scope-title"><h2 id="scope-title">适用范围与运营者</h2>{intro}</section>{''.join(sections)}
<a class="back-top" href="#top">返回顶部 ↑</a></article></div></main>
<footer><span>纪元急袭 · 隐私政策</span><span>{source['policy_version']}</span><a href="mailto:{html.escape(email,quote=True)}">{html.escape(email)}</a></footer>
</body></html>'''
    (SITE / "index.html").write_text(page, encoding="utf-8")
    markdown = build_markdown(source)
    (DOCS / "privacy-policy.zh-CN.md").write_text(markdown, encoding="utf-8")
    (SITE / "privacy-policy.md").write_text(markdown, encoding="utf-8")
    shutil.copy2(docx, SITE / "privacy-policy.docx")
    logo = ROOT / "output/imagegen/logo-selection/2026-10-07-source-matched-v4/front-bust-no-text/01-pixel-crest.png"
    if not logo.exists():
        logo = ROOT / "godot/assets/ui/pixel/app-icon.png"
    with Image.open(logo) as image:
        image.convert("RGBA").resize((192, 192), Image.Resampling.LANCZOS).save(SITE / "assets/knight.png")
    (DOCS / "policy.json").write_text(json.dumps(source, ensure_ascii=False, indent=2), encoding="utf-8")
    for path in SITE.rglob("*"):
        if path.is_file() and path.name in (".env", "identity.json", "policy.json", "privacy-policy-template.docx"):
            raise RuntimeError("Nonpublic file found in deployment directory: " + str(path))


def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    source, identity = load_source()
    docx = build_docx(source, identity)
    build_site(source, identity, docx)
    print(json.dumps({"docx": str(docx), "site": str(SITE), "sections": len(source["sections"]),
                      "template_sha256": hashlib.sha256(TEMPLATE.read_bytes()).hexdigest()}, ensure_ascii=False))


if __name__ == "__main__":
    main()
