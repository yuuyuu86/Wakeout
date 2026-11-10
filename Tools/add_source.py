#!/usr/bin/env python3
"""Wakeout.xcodeproj に Swift ファイルを登録する。

    python3 Tools/add_source.py Wakeout/Mission/StepDetector.swift [--target widget]

pbxproj を直接書き換える。プロジェクト全体を作り直さないので、
Xcode で設定した署名やケイパビリティを壊さない。

--target を省略するとアプリ本体に追加する。Shared/ のファイルなど
両方に入れたい場合は `--target app --target widget` のように 2 回指定する。
"""
import argparse
import hashlib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBXPROJ = os.path.join(ROOT, "Wakeout.xcodeproj", "project.pbxproj")

# Sources ビルドフェーズを見分けるための、各ターゲットの既知のファイル。
# フェーズ自体に名前が無いので、確実にそのターゲットにしか無いファイルで判別する。
#
# 同じ文字列は PBXBuildFile セクションにも出てくる（末尾が `};`）。
# ビルドフェーズの一覧は末尾が `,` なので、そちらだけを拾うこと。
# 取り違えるとファイルの末尾（閉じ括弧の外）に書き込んでプロジェクトが壊れる。
TARGET_MARKERS = {
    "app": "AlarmScheduler.swift in Sources",
    "widget": "NextAlarmWidget.swift in Sources",
}


def uid(key, taken):
    """24 桁の一意な ID。既存と衝突しないことを確認して返す。"""
    for salt in range(1000):
        value = hashlib.sha1(f"{key}:{salt}".encode()).hexdigest().upper()[:24]
        if value not in taken:
            taken.add(value)
            return value
    raise RuntimeError("一意な ID を作れませんでした")


def group_uid_for(source, text):
    """そのファイルを入れるグループ（フォルダ）の ID を探す。"""
    directory = os.path.basename(os.path.dirname(source))
    # 例:  4E1... /* Mission */ = { isa = PBXGroup;
    pattern = re.compile(
        r"([0-9A-F]{24}) /\* " + re.escape(directory) + r" \*/ = \{\s*isa = PBXGroup;",
        re.MULTILINE,
    )
    found = pattern.search(text)
    if not found:
        raise SystemExit(f"グループ '{directory}' が見つかりません。先に Xcode で作ってください。")
    return found.group(1)


def insert_after(text, anchor, addition):
    index = text.index(anchor) + len(anchor)
    return text[:index] + addition + text[index:]


def add(source, targets):
    path = os.path.join(ROOT, source)
    if not os.path.exists(path):
        raise SystemExit(f"ファイルがありません: {source}")

    text = open(PBXPROJ).read()
    base = os.path.basename(source)

    if f"/* {base} */ = {{isa = PBXFileReference" in text:
        print(f"すでに登録済み: {base}")
        return

    taken = set(re.findall(r"\b[0-9A-F]{24}\b", text))
    file_ref = uid("fref:" + source, taken)

    # 1. PBXFileReference
    text = insert_after(
        text,
        "/* Begin PBXFileReference section */",
        f'\n\t\t{file_ref} /* {base} */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = sourcecode.swift; path = {base}; sourceTree = "<group>"; }};',
    )

    # 2. グループに並べる
    group = group_uid_for(source, text)
    group_children = re.search(
        r"(" + group + r" /\* [^*]+ \*/ = \{\s*isa = PBXGroup;\s*children = \()",
        text,
    )
    text = insert_after(text, group_children.group(1), f"\n\t\t\t\t{file_ref} /* {base} */,")

    # 3. ターゲットごとに PBXBuildFile と Sources フェーズ
    for target in targets:
        build_file = uid(f"bfile:{target}:{source}", taken)
        text = insert_after(
            text,
            "/* Begin PBXBuildFile section */",
            f"\n\t\t{build_file} /* {base} in Sources */ = {{isa = PBXBuildFile; "
            f"fileRef = {file_ref} /* {base} */; }};",
        )

        marker = TARGET_MARKERS[target]
        # ビルドフェーズ側（末尾がカンマ）の行だけを探す。
        phase_entry = re.search(
            r"\n(\t+)[0-9A-F]{24} /\* " + re.escape(marker) + r" \*/,",
            text,
        )
        if not phase_entry:
            raise SystemExit(f"{target} の Sources フェーズを特定できません（目印: {marker}）")
        indent = phase_entry.group(1)
        text = (
            text[: phase_entry.start()]
            + f"\n{indent}{build_file} /* {base} in Sources */,"
            + text[phase_entry.start():]
        )

    open(PBXPROJ, "w").write(text)
    print(f"追加: {base} → {', '.join(targets)}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("sources", nargs="+")
    parser.add_argument(
        "--target", action="append", choices=sorted(TARGET_MARKERS), default=None
    )
    args = parser.parse_args()
    targets = args.target or ["app"]

    for source in args.sources:
        add(source, targets)


if __name__ == "__main__":
    main()
