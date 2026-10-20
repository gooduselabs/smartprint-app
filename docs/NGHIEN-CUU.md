# Nghiên cứu: Smart Printer: Print Documents (Rhythmix OU)

**Gói:** `tech.kma.smart.printer` · Ra mắt 05/2024 · ~16,5 triệu lượt cài · 4,3★ (~180k đánh giá) · ~1,1 triệu MAU, ước tính ~100k USD/tháng (100% IAP, không quảng cáo – AppGoblin). Bản iOS tương tự: "Smart Printer App: iPrint".

## Tính năng thực tế
- **In đa năng**: in qua WiFi tới hầu hết máy in phun/laser/nhiệt (HP, Canon, Epson, Brother…) – thực chất dựa trên Android Print Framework / IPP / Mopria.
- **In ảnh**: JPG, PNG, GIF, WEBP; **in nhiều ảnh trên một tờ**.
- **In tài liệu**: PDF, Word, Excel, PowerPoint, TXT, CSV.
- **Máy quét PDF**: chụp tài liệu bằng camera, nhiều trang → PDF.
- **In trang web**, **tệp đính kèm email**, Google Drive/cloud (qua bộ chọn tệp).
- **Xem trước** trước khi in; tuỳ chọn số bản, khổ giấy, hướng, trang/tờ.
- **Thư viện 100+ mẫu** (thiệp, lịch, khung ảnh), cập nhật hàng tháng.

## Kiếm tiền
- Paywall ngay khi mở app, **dùng thử 3 ngày → gói tuần** tự gia hạn (kèm gói năm/khuyến mãi). Hầu hết tính năng bị khoá sau paywall.
- Đánh giá xấu chủ yếu: bị trừ tiền sau trial, paywall gắt, không kết nối được vài máy in.

## Khác biệt của SmartPrint (bản clone)
- **AI chạy trên máy** (Google AI Edge – Gemma 3 1B qua MediaPipe LLM Inference): tóm tắt/dịch văn bản quét; **OCR** bằng ML Kit; tự động làm nét ảnh. Model tải lần đầu, không đóng gói.
- Paywall minh bạch, không lừa trial.

## Kế hoạch MVP
| Giai đoạn | Nội dung |
|---|---|
| MVP (v0.1) | In PDF/ảnh/DOCX (chuyển đổi qua server), sửa ảnh (cắt/xoay/lọc), web → PDF, máy quét nhiều trang, in qua hệ thống + IPP trực tiếp (mDNS), lịch sử in, paywall giả lập, AI on-device |
| Backend | Auth email, hồ sơ, đồng bộ lịch sử in, lưu tài liệu cloud, chuyển web/Office → PDF (LibreOffice), stub gói thuê bao |
| v0.2 | Google Play Billing thật, nhiều ảnh/tờ, thư viện mẫu, Drive/email share-intent |
