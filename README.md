# HookTrans

แปลบทพูดในเกมแบบ real-time แล้วแสดงเป็น overlay เขียนด้วย Flutter/Dart

แหล่งข้อความมี 2 แบบตาม OS:

| OS | แหล่งข้อความ | ความแม่น |
|---|---|---|
| Windows | memory hook ผ่าน TextractorCLI | ได้ข้อความตรงจากเกม 100% |
| macOS | จับหน้าจอเฉพาะกรอบ subtitle + OCR ด้วย Apple Vision | ขึ้นกับฟอนต์/พื้นหลัง |

แปลด้วย local LLM ผ่าน LM Studio หรือ Google Translate เมื่อไม่มีโมเดลในเครื่อง

## macOS (โหมด OCR)

```bash
flutter run -d macos
```

1. เปิดเกมแบบ windowed ให้เห็นกล่องข้อความ
2. ใน HookTrans กด **เลือกพื้นที่บนหน้าจอ** ครั้งแรก macOS จะขอสิทธิ์ *Screen Recording*
   อนุญาตที่ System Settings → Privacy & Security → Screen Recording แล้วเปิดแอปใหม่
3. ลากกรอบรอบกล่องข้อความแล้วกด **ใช้พื้นที่นี้** แอปจะเริ่มอ่านทันที
4. เลือกภาษาในเกม (OCR) ให้ตรง เช่น ญี่ปุ่น + อังกฤษ
5. กด **เปิด Overlay** แล้วลาก overlay ไปวางที่ไหนก็ได้ (overlay ของแอปเองจะไม่ถูก OCR อ่านซ้ำ)

แอปจับภาพเฉพาะกรอบที่เลือกทุก 200 ms เทียบภาพก่อน ถ้าไม่เปลี่ยนจะไม่ OCR
และข้ามเฟรมที่ต่างจากบรรทัดก่อนแค่ 1-2 ตัวอักษร (noise ของ OCR)

## Windows (โหมด memory hook)

จุดต่างจาก textractor-translator: ไม่ต้องเปิด Textractor GUI, ไม่ต้องอ่าน hex address
เลือกเกมจากรายชื่อ กดเดินบทพูด 2-3 ครั้ง แอปจะเลือก thread บทพูดให้เอง แล้วเปิด overlay

สิ่งที่ต้องมี

1. **Windows 10/11**
2. **Textractor** ดาวน์โหลด zip จาก <https://github.com/Artikash/Textractor/releases>
   แตกไฟล์แล้วเอาโฟลเดอร์ `x86` และ `x64` ไปวางใน `textractor/` ข้าง `hooktrans.exe`
   (ต้องมี `textractor/x86/TextractorCLI.exe` และ `textractor/x64/TextractorCLI.exe`)
   หรือชี้ path เองได้ที่หน้า "ขั้นสูง"
3. **LM Studio** (ถ้าจะใช้ local LLM) โหลดโมเดลแล้วกด *Start Server* ที่แท็บ Developer
   ค่าเริ่มต้นคือ `http://localhost:1234/v1` หรือใช้ CLI: `lms server start` แล้ว `lms load <model>`
   - ถ้า LM Studio เปิด *Require authentication* ให้สร้าง token ที่ Developer → Server settings → Manage Tokens
     แล้ววางในช่อง API token ของแอป (หรือเปิดแอปด้วย `open hooktrans.app --env HOOKTRANS_LM_TOKEN=...` ครั้งเดียว แอปจะจำไว้)
   - โมเดลตระกูล reasoning (Qwen3.x, DeepSeek) ต้องเปิดสวิตช์ "ปิด thinking" ในแอป (ส่ง `reasoning_effort: none`)
     ไม่งั้นโมเดลจะคิดจนหมดโควตา token แล้วตอบว่าง
   - ทดสอบแล้วกับ `qwen/qwen3.6-35b-a3b` บน Apple Silicon: แปลญี่ปุ่น→ไทยได้ดี ~0.7 วินาทีต่อบรรทัด
     โมเดลเล็กกว่าที่ใช้ได้: `qwen3-4b`, `gemma-3-4b`, `qwen2.5-7b-instruct`
4. ถ้าไม่มี LM Studio สลับเป็น **Google Translate** ได้ (ใช้ endpoint สาธารณะ ไม่ต้องใช้ key ต้องต่อเน็ต)

Build: `flutter build windows` ไฟล์อยู่ที่ `build/windows/x64/runner/Release/` วางโฟลเดอร์ `textractor/` ไว้ข้าง exe

วิธีใช้

1. เปิดเกมก่อน แล้วเปิด HookTrans
2. **เลือกเกม** จากรายชื่อซ้ายมือ (แอปตรวจ 32/64-bit ให้เอง และเลือก TextractorCLI ให้ตรง)
3. **เครื่องมือแปล** เลือก LM Studio หรือ Google และภาษาปลายทาง
4. กดเดินบทพูดในเกม 2-3 ครั้ง ดูช่อง **Thread บทพูด** ว่าแถวที่ถูกปักหมุดเป็นบทพูดจริง
   ถ้าไม่ใช่ คลิกแถวที่ถูกต้อง
5. กด **เปิด Overlay** หน้าต่างจะย่อเป็นแถบลอยอยู่บนสุด ลากไปวางใต้กล่องข้อความของเกมได้
   ปุ่มบนแถบ: ขนาดตัวอักษร, ความทึบ, ซ่อนต้นฉบับ, กลับหน้าตั้งค่า

เกมต้องเล่นแบบ windowed หรือ borderless ไม่งั้น overlay จะถูกเกมบัง

## เกมที่ hook ไม่ขึ้นบทพูด

บางเกมต้องใช้ H-code (หาได้จากชุมชน เช่น vndb) ใส่ที่หน้า "ขั้นสูง" แล้วกดส่ง
รูปแบบเดียวกับ Textractor เช่น `/HS-4@1234:game.exe`

## โครงสร้างโค้ด

```
lib/core/textractor_cli.dart   เปิด TextractorCLI.exe, ส่งคำสั่ง attach/detach/hookcode (stdin/stdout เป็น UTF-16LE)
lib/core/textractor_line.dart  parser บรรทัด [handle:pid:addr:ctx:ctx2:name:hookcode] text
lib/core/text_cleaner.dart     ลบตัวอักษรซ้ำ/ประโยคซ้ำที่ hook ชอบส่งมา
lib/core/thread_picker.dart    heuristic เลือก thread บทพูด (ความยาว, ความหลากหลาย, ความถี่, ความสดใหม่)
lib/core/pipeline.dart         รอข้อความนิ่ง 250ms, cache, ส่งบริบทบรรทัดก่อนหน้าไปกับคำขอแปล
lib/core/translator.dart       LM Studio (OpenAI-compatible, streaming)
lib/core/google_translator.dart Google Translate fallback
lib/core/process_list.dart     รายชื่อ process ที่มีหน้าต่าง + ตรวจ 32/64-bit จาก PE header
lib/core/screen_ocr_source.dart (macOS) วนจับภาพกรอบ subtitle ผ่าน method channel แล้วส่ง text เข้า pipeline
macos/Runner/ScreenChannel.swift ScreenCaptureKit + Vision OCR, ข้ามเฟรมที่ภาพไม่เปลี่ยน
lib/ui/                        หน้าตั้งค่า และ overlay
```

ทดสอบ: `flutter test`
