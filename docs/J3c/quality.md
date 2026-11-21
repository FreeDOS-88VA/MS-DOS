# M2 — Conversion quality

**Gate:** both selectors on VA 640 KiB and VA2 256/640 KiB; 22 fixed
romaji readings, with shots after each of the first ten HENKAN taps.
Each reading starts from a fresh boot of the M1 image. The two phrases
also have separate runs that move the focus right six times after the
first conversion, without cycling the text.

Each cell is **visible first candidate / HENKAN taps to the expected
text**. `>10` means the full expected string was not visible after any
of the ten taps. It does **not** mean that changing focus, resizing a
segment or trying another spelling could not reach it. The segmentation
rows report focus boundaries in the *displayed candidate*, not offsets
in the original romaji. Consecutive identical focus snapshots are elided;
revisits after a move are retained.

[`quality.py`](quality.py) inverts the TVRAM JIS cell encoding to
Shift-JIS and decodes it using CP932 (including the telephone symbol on
VA2). It reads focus from the ROM's system-row attributes or the FEP's
brackets. Expected strings are inputs to the comparison, not manually
transcribed results. No dictionary data was extracted.

```sh
python3 -B docs/J3c/run.py "$VAEG" "$ROMS" "$GATE_D88" "$S/m2" \
  --cistat 1000:09AA --prefix quality- --prefix segments-
PYTHONPATH="$VAEG_SOURCE/tools/qa" python3 -B docs/J3c/quality.py "$S/m2"
```

All **144 cases reached `exit`**, with **1,824 TVRAM shots**. Within
each model/RAM configuration, ROM and FEP agreed on every first
candidate, target rank and first-candidate focus walk. VA: **18/22**
first and **20/22** by ten taps, in either mode. VA2 at both RAM sizes:
**17/22** first and **21/22** by ten. These counts are for this corpus
only, not a general conversion-accuracy estimate.

| Reading | Expected | va-640 ROM | va-640 FEP | va2-256 ROM | va2-256 FEP | va2-640 ROM | va2-640 FEP |
|---|---|---|---|---|---|---|---|
| nihongo | 日本語 | 日本語 / 1 | 日本語 / 1 | 日本語 / 1 | 日本語 / 1 | 日本語 / 1 | 日本語 / 1 |
| kanji | 漢字 | 漢字 / 1 | 漢字 / 1 | 漢字 / 1 | 漢字 / 1 | 漢字 / 1 | 漢字 / 1 |
| henkan | 変換 | 変換 / 1 | 変換 / 1 | 変換 / 1 | 変換 / 1 | 変換 / 1 | 変換 / 1 |
| toukyou | 東京 | 東京 / 1 | 東京 / 1 | 東京 / 1 | 東京 / 1 | 東京 / 1 | 東京 / 1 |
| gakkou | 学校 | 学校 / 1 | 学校 / 1 | 学校 / 1 | 学校 / 1 | 学校 / 1 | 学校 / 1 |
| sensei | 先生 | 先制 / 2 | 先制 / 2 | 先生 / 1 | 先生 / 1 | 先生 / 1 | 先生 / 1 |
| denwa | 電話 | 電話 / 1 | 電話 / 1 | 電話 / 1 | 電話 / 1 | 電話 / 1 | 電話 / 1 |
| jikan | 時間 | 時間 / 1 | 時間 / 1 | 時間 / 1 | 時間 / 1 | 時間 / 1 | 時間 / 1 |
| keisanki | 計算機 | 計算器 / 2 | 計算器 / 2 | 計算器 / 2 | 計算器 / 2 | 計算器 / 2 | 計算器 / 2 |
| shinbun | 新聞 | 新聞 / 1 | 新聞 / 1 | 新聞 / 1 | 新聞 / 1 | 新聞 / 1 | 新聞 / 1 |
| watashi | 私 | 私 / 1 | 私 / 1 | 渡し / 3 | 渡し / 3 | 渡し / 3 | 渡し / 3 |
| kyou | 今日 | 今日 / 1 | 今日 / 1 | 今日 / 1 | 今日 / 1 | 今日 / 1 | 今日 / 1 |
| ashita | 明日 | 明日 / 1 | 明日 / 1 | 明日 / 1 | 明日 / 1 | 明日 / 1 | 明日 / 1 |
| hon | 本 | 本 / 1 | 本 / 1 | 本 / 1 | 本 / 1 | 本 / 1 | 本 / 1 |
| kuruma | 車 | 車 / 1 | 車 / 1 | 車 / 1 | 車 / 1 | 車 / 1 | 車 / 1 |
| yama | 山 | 山 / 1 | 山 / 1 | 山 / 1 | 山 / 1 | 山 / 1 | 山 / 1 |
| kawa | 川 | 川 / 1 | 川 / 1 | 川 / 1 | 川 / 1 | 川 / 1 | 川 / 1 |
| mizu | 水 | 水 / 1 | 水 / 1 | みず / 7 | みず / 7 | みず / 7 | みず / 7 |
| sakura | 桜 | 桜 / 1 | 桜 / 1 | さくら / 2 | さくら / 2 | さくら / 2 | さくら / 2 |
| neko | 猫 | 猫 / 1 | 猫 / 1 | 猫 / 1 | 猫 / 1 | 猫 / 1 | 猫 / 1 |
| nihongowohanasu | 日本語を話す | 日本語を離す / >10 | 日本語を離す / >10 | 日本語を離す / >10 | 日本語を離す / >10 | 日本語を離す / >10 | 日本語を離す / >10 |
| kyouhaiitenkidesu | 今日はいい天気です | 今日は言天気です / >10 | 今日は言天気です / >10 | 今日はいい天気です / 1 | 今日はいい天気です / 1 | 今日はいい天気です / 1 | 今日はいい天気です / 1 |

| Reading | Configuration | Mode | Focus walk (first candidate, then Right × 6) |
|---|---|---|---|
| nihongowohanasu | va-640 | ROM | [日本語を]離す → 日本語を[離す] → [日本語を]離す → 日本語を[離す] → [日本語を]離す → 日本語を[離す] → [日本語を]離す |
| nihongowohanasu | va-640 | FEP | [日本語を]離す → 日本語を[離す] → [日本語を]離す → 日本語を[離す] → [日本語を]離す → 日本語を[離す] → [日本語を]離す |
| nihongowohanasu | va2-256 | ROM | [日本語を]離す → 日本語を[離す] → [日本語を]離す → 日本語を[離す] → [日本語を]離す → 日本語を[離す] → [日本語を]離す |
| nihongowohanasu | va2-256 | FEP | [日本語を]離す → 日本語を[離す] → [日本語を]離す → 日本語を[離す] → [日本語を]離す → 日本語を[離す] → [日本語を]離す |
| nihongowohanasu | va2-640 | ROM | [日本語を]離す → 日本語を[離す] → [日本語を]離す → 日本語を[離す] → [日本語を]離す → 日本語を[離す] → [日本語を]離す |
| nihongowohanasu | va2-640 | FEP | [日本語を]離す → 日本語を[離す] → [日本語を]離す → 日本語を[離す] → [日本語を]離す → 日本語を[離す] → [日本語を]離す |
| kyouhaiitenkidesu | va-640 | ROM | [今日は]言天気です → 今日は[言]天気です → 今日は言[天気です] → [今日は]言天気です → 今日は[言]天気です → 今日は言[天気です] → [今日は]言天気です |
| kyouhaiitenkidesu | va-640 | FEP | [今日は]言天気です → 今日は[言]天気です → 今日は言[天気です] → [今日は]言天気です → 今日は[言]天気です → 今日は言[天気です] → [今日は]言天気です |
| kyouhaiitenkidesu | va2-256 | ROM | [今日はいい]天気です → 今日はいい[天気です] → [今日はいい]天気です → 今日はいい[天気です] → [今日はいい]天気です → 今日はいい[天気です] → [今日はいい]天気です |
| kyouhaiitenkidesu | va2-256 | FEP | [今日はいい]天気です → 今日はいい[天気です] → [今日はいい]天気です → 今日はいい[天気です] → [今日はいい]天気です → 今日はいい[天気です] → [今日はいい]天気です |
| kyouhaiitenkidesu | va2-640 | ROM | [今日はいい]天気です → 今日はいい[天気です] → [今日はいい]天気です → 今日はいい[天気です] → [今日はいい]天気です → 今日はいい[天気です] → [今日はいい]天気です |
| kyouhaiitenkidesu | va2-640 | FEP | [今日はいい]天気です → 今日はいい[天気です] → [今日はいい]天気です → 今日はいい[天気です] → [今日はいい]天気です → 今日はいい[天気です] → [今日はいい]天気です |
