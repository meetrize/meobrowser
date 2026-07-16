#!/usr/bin/env python3
"""MeoBrowser Captcha Assist helper — OCR (ddddocr) and math parsing."""

from __future__ import annotations

import argparse
import json
import re
import sys


def emit(payload: dict) -> None:
    print(json.dumps(payload, ensure_ascii=False))
    sys.stdout.flush()


def cmd_ocr(image_path: str) -> int:
    try:
        import ddddocr  # type: ignore
    except ImportError:
        emit({
            "ok": False,
            "error": "未安装 ddddocr。请运行：pip3 install ddddocr",
        })
        return 2

    try:
        with open(image_path, "rb") as f:
            data = f.read()
        ocr = ddddocr.DdddOcr(show_ad=False)
        text = ocr.classification(data)
        text = (text or "").strip()
        if not text:
            emit({"ok": False, "error": "OCR 未识别出文本"})
            return 1
        emit({"ok": True, "text": text})
        return 0
    except Exception as exc:  # noqa: BLE001
        emit({"ok": False, "error": str(exc)})
        return 1


def _normalize_math(expr: str) -> str:
    s = expr.strip()
    s = re.sub(r"[=?？\s]+", " ", s)
    s = s.replace("×", "*").replace("÷", "/").replace("x", "*").replace("X", "*")
    s = re.sub(r"\s+", "", s)
    return s


def cmd_math(expression: str) -> int:
    s = _normalize_math(expression)
    if not s:
        emit({"ok": False, "error": "算术表达式为空"})
        return 1

    m = re.match(r"^(-?\d+)([\+\-\*/])(-?\d+)$", s)
    if not m:
        emit({"ok": False, "error": f"不支持的算术格式：{expression!r}"})
        return 1

    a = int(m.group(1))
    op = m.group(2)
    b = int(m.group(3))
    if op == "+":
        result = a + b
    elif op == "-":
        result = a - b
    elif op == "*":
        result = a * b
    elif op == "/":
        if b == 0:
            emit({"ok": False, "error": "除数为零"})
            return 1
        result = a // b if a % b == 0 else a / b
    else:
        emit({"ok": False, "error": f"未知运算符：{op}"})
        return 1

    if isinstance(result, float) and result.is_integer():
        result = int(result)
    emit({"ok": True, "text": str(result)})
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="MeoBrowser captcha helper")
    sub = parser.add_subparsers(dest="command", required=True)

    ocr_p = sub.add_parser("ocr", help="OCR image file")
    ocr_p.add_argument("image", help="path to PNG/JPEG")

    math_p = sub.add_parser("math", help="evaluate simple math expression")
    math_p.add_argument("expression", help='e.g. "3 + 5 = ?"')

    args = parser.parse_args()
    if args.command == "ocr":
        return cmd_ocr(args.image)
    if args.command == "math":
        return cmd_math(args.expression)
    emit({"ok": False, "error": "unknown command"})
    return 1


if __name__ == "__main__":
    sys.exit(main())
