import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class BillPdfService {
  BillPdfService._();

  static const String _regularFontPath =
      'assets/fonts/NotoSansDevanagari-Regular.ttf';
  static const String _boldFontPath =
      'assets/fonts/NotoSansDevanagari-Bold.ttf';

  // Copy your logo to assets/images/atul_logo.png and register it in pubspec.yaml.
  static const String _logoPath = 'assets/images/atul_logo.png';

  static final PdfColor _green = PdfColor.fromHex('#176B45');
  static final PdfColor _deepGreen = PdfColor.fromHex('#104A31');
  static final PdfColor _lightGreen = PdfColor.fromHex('#EAF5EF');
  static final PdfColor _gold = PdfColor.fromHex('#F4A340');
  static final PdfColor _pink = PdfColor.fromHex('#E92F5B');
  static final PdfColor _ink = PdfColor.fromHex('#263238');
  static final PdfColor _muted = PdfColor.fromHex('#65736C');
  static final PdfColor _line = PdfColor.fromHex('#D8E5DD');
  static final PdfColor _softGold = PdfColor.fromHex('#FFF4E5');
  static final PdfColor _white = PdfColors.white;

  static String _string(Object? value, [String fallback = '—']) {
    if (value == null) return fallback;
    final result = value.toString().trim();
    return result.isEmpty ? fallback : result;
  }

  static double _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _money(Object? value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(_number(value));
  }

  static String _date(Object? value) {
    final raw = _string(value, '');
    if (raw.isEmpty) return '—';
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }

  static String _monthLabel(Object? value) {
    final raw = _string(value, '');
    try {
      final parts = raw.split('-');
      if (parts.length == 2) {
        return DateFormat('MMMM yyyy')
            .format(DateTime(int.parse(parts[0]), int.parse(parts[1])));
      }
    } catch (_) {}
    return raw.isEmpty ? 'Monthly Bill' : raw;
  }

  static Future<pw.Font> _loadRegularFont() async {
    final data = await rootBundle.load(_regularFontPath);
    return pw.Font.ttf(data);
  }

  static Future<pw.Font> _loadBoldFont() async {
    final data = await rootBundle.load(_boldFontPath);
    return pw.Font.ttf(data);
  }

  static Future<pw.MemoryImage?> _loadLogo() async {
    try {
      final data = await rootBundle.load(_logoPath);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      // The PDF still works if the optional logo asset has not been added.
      return null;
    }
  }

  static Future<void> generateAndShare({
    required Map<String, Object?> customer,
    required Map<String, Object?> bill,
    required List<Map<String, Object?>> entries,
    required String businessName,
    required String businessPhone,
    required String businessAddress,
    String upiId = '',
    String payeeName = '',
    bool showDailyDeliveryDetails = true,
    String invoiceTitle = 'MONTHLY MILK BILL',
  }) async {
    final regularFont = await _loadRegularFont();
    final boldFont = await _loadBoldFont();
    final logo = await _loadLogo();

    final pdf = pw.Document(
      title: '$businessName Monthly Milk Bill',
      author: businessName,
      subject: 'Monthly milk delivery invoice',
    );

    final theme = pw.ThemeData.withFont(
      base: regularFont,
      bold: boldFont,
    );

    final customerName = _string(customer['name'], 'Customer');
    final customerMobile = _string(customer['mobile']);
    final customerAddress = _string(customer['address']);
    final milkType = _string(customer['milk_type'], 'Milk');
    final billingMonth = _monthLabel(bill['billing_month']);
    final billNumber = _string(bill['id']);
    final serviceCharge = _number(
      bill['service_charge'] ?? bill['monthly_service_charge'],
    );
    final milkAmount = _number(bill['milk_amount']);
    final previousDue = _number(bill['previous_due']);
    final paymentsReceived = _number(bill['payments_received']);
    final finalBalance = _number(bill['final_balance']);
    final billStatus = _string(bill['status'], 'unpaid').toUpperCase();
    final upiConfigured = upiId.contains('@') && upiId != 'YOUR_UPI_ID';
    final upiPaymentUri = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': upiId,
        'pn': payeeName.isEmpty ? businessName : payeeName,
        'am': finalBalance.toStringAsFixed(2),
        'cu': 'INR',
        'tn': 'Milk bill ${bill['billing_month'] ?? ''}',
      },
    );

    final dailyRows = <List<String>>[];
    double calculatedMilkTotal = 0;
    double calculatedQuantity = 0;

    for (final entry in entries) {
      final quantity = _number(entry['quantity']);
      final rate = _number(entry['rate']);
      final amount = quantity * rate;
      calculatedQuantity += quantity;
      calculatedMilkTotal += amount;

      dailyRows.add([
        _date(entry['entry_date']),
        quantity.toStringAsFixed(2),
        _money(rate),
        _money(amount),
        _string(entry['delivered'] == 1 || entry['delivered'] == true
            ? 'Delivered'
            : '—'),
      ]);
    }

    // Use stored bill total for the invoice summary; daily total is shown in table footer.
    final tableMilkTotal = calculatedMilkTotal;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        margin: const pw.EdgeInsets.fromLTRB(34, 28, 34, 34),
        header: (context) => pw.SizedBox(),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: _line, width: 0.8),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Thank you for choosing $businessName!',
                style: pw.TextStyle(color: _muted, fontSize: 8),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(color: _muted, fontSize: 8),
              ),
            ],
          ),
        ),
        build: (context) => [
          // Brand header
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logo != null)
                pw.Container(
                  width: 112,
                  height: 72,
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                )
              else
                pw.Container(
                  width: 112,
                  height: 72,
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    'ATUL',
                    style: pw.TextStyle(
                      fontSize: 30,
                      fontWeight: pw.FontWeight.bold,
                      color: _green,
                    ),
                  ),
                ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      businessName,
                      style: pw.TextStyle(
                        fontSize: 21,
                        fontWeight: pw.FontWeight.bold,
                        color: _deepGreen,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Committed to Purity',
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: _muted,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                    pw.SizedBox(height: 7),
                    pw.Text(
                      'Phone: $businessPhone',
                      style: pw.TextStyle(fontSize: 9, color: _ink),
                    ),
                    pw.Text(
                      'Address: $businessAddress',
                      style: pw.TextStyle(fontSize: 9, color: _ink),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  if (upiConfigured)
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: upiPaymentUri.toString(),
                      width: 70,
                      height: 70,
                    )
                  else
                    pw.Container(
                      width: 70,
                      height: 70,
                      alignment: pw.Alignment.center,
                      decoration: pw.BoxDecoration(
                        color: _white,
                        border: pw.Border.all(color: _line),
                      ),
                      child: pw.Text(
                        'UPI QR\nnot set',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(fontSize: 8, color: _muted),
                      ),
                    ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'SCAN TO PAY',
                    style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: _deepGreen),
                  ),
                  pw.Text('Due ${_money(finalBalance)}', style: pw.TextStyle(fontSize: 7, color: _ink)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 13),
          pw.Container(height: 3, color: _gold),
          pw.SizedBox(height: 12),

          // Invoice title strip
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            decoration: pw.BoxDecoration(
              color: _deepGreen,
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    invoiceTitle,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: _white,
                    ),
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'BILL NO: $billNumber',
                      style: pw.TextStyle(fontSize: 8, color: _white),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'MONTH: $billingMonth',
                      style: pw.TextStyle(fontSize: 8, color: _white),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          _sectionTitle('CUSTOMER DETAILS'),
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(1.0),
              1: pw.FlexColumnWidth(2.2),
              2: pw.FlexColumnWidth(1.0),
              3: pw.FlexColumnWidth(1.8),
            },
            border: pw.TableBorder.all(color: _line, width: 0.6),
            children: [
              _customerRow(
                'Customer Name',
                customerName,
                'Mobile Number',
                customerMobile,
              ),
              _customerRow(
                'Address',
                customerAddress,
                'Milk Type',
                milkType,
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          if (showDailyDeliveryDetails) ...[
          _sectionTitle('DAILY DELIVERY DETAILS'),
          if (dailyRows.isEmpty)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: _lightGreen,
                border: pw.Border.all(color: _line),
              ),
              child: pw.Text(
                'No delivered milk entries were found for this billing month.',
                style: pw.TextStyle(fontSize: 9, color: _muted),
              ),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: [
                'Date',
                'Qty (L)',
                'Rate',
                'Amount',
                'Delivery',
              ],
              data: dailyRows,
              headerDecoration: pw.BoxDecoration(color: _lightGreen),
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: _deepGreen,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
              },
              border: pw.TableBorder.all(color: _line, width: 0.5),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 5,
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.5),
                1: pw.FlexColumnWidth(0.9),
                2: pw.FlexColumnWidth(1.1),
                3: pw.FlexColumnWidth(1.3),
                4: pw.FlexColumnWidth(1.0),
              },
            ),
          pw.SizedBox(height: 5),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 7,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F7FAF8'),
              border: pw.Border.all(color: _line, width: 0.5),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Total delivered quantity: ${calculatedQuantity.toStringAsFixed(2)} L',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: _deepGreen,
                    ),
                  ),
                ),
                pw.Text(
                  'Entry total: ${_money(tableMilkTotal)}',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: _deepGreen,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          ],

          _sectionTitle('BILL SUMMARY'),
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(1),
            },
            border: pw.TableBorder.all(color: _line, width: 0.5),
            children: [
              if (bill['extra_items'] is List)
                ...(bill['extra_items'] as List).whereType<Map>().map((item) {
                  final label = _string(item['label'], 'Extra item');
                  final quantity = _number(item['quantity']);
                  final unit = _string(item['unit']);
                  final price = _number(item['price']);
                  final total = _number(item['total']);
                  return _summaryRow(
                    '$label (${quantity.toStringAsFixed(2)} $unit × ${_money(price)})',
                    _money(total),
                  );
                }),
              if (bill['total_milk_quantity'] != null)
                _summaryRow('Total Milk', '${_number(bill['total_milk_quantity']).toStringAsFixed(2)} L'),
              if (bill['milk_rate'] != null)
                _summaryRow('Milk Price / L', _money(bill['milk_rate'])),
              _summaryRow('Milk Charges', _money(milkAmount)),
              _summaryRow('Monthly Service Charge', _money(serviceCharge)),
              _summaryRow('Previous Due', _money(previousDue)),
              _summaryRow('Payments Received', '− ${_money(paymentsReceived)}'),
            ],
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            decoration: pw.BoxDecoration(
              color: _softGold,
              border: pw.Border.all(color: _gold, width: 0.9),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'TOTAL AMOUNT DUE',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: _deepGreen,
                    ),
                  ),
                ),
                pw.Text(
                  _money(finalBalance),
                  style: pw.TextStyle(
                    fontSize: 19,
                    fontWeight: pw.FontWeight.bold,
                    color: _deepGreen,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          _sectionTitle('PAYMENT DETAILS'),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: _lightGreen,
              border: pw.Border.all(color: _line, width: 0.6),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.SizedBox(
                      width: 100,
                      child: pw.Text(
                        'Payment Status',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: _deepGreen,
                        ),
                      ),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: pw.BoxDecoration(
                        color: finalBalance <= 0
                            ? _green
                            : _pink,
                        borderRadius: pw.BorderRadius.circular(3),
                      ),
                      child: pw.Text(
                        finalBalance <= 0 ? 'PAID' : billStatus,
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: _white,
                        ),
                      ),
                    ),
                  ],
                ),
                if (upiId.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'UPI ID: $upiId',
                    style: pw.TextStyle(fontSize: 9, color: _ink),
                  ),
                ],
                if (payeeName.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Payee Name: $payeeName',
                    style: pw.TextStyle(fontSize: 9, color: _ink),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 13),
          pw.Container(height: 1, color: _line),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              'Thank you for choosing $businessName.',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _deepGreen,
              ),
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Center(
            child: pw.Text(
              'Freshness, quality and purity — delivered to your doorstep.',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 8, color: _muted),
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Center(
            child: pw.Text(
              'For billing queries, contact $businessPhone.',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 8, color: _muted),
            ),
          ),
        ],
      ),
    );

    final Uint8List bytes = await pdf.save();
    final safeCustomerName = customerName
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final safeMonth = _string(bill['billing_month'], 'bill')
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Atul_Milk_Bill_${safeCustomerName}_$safeMonth.pdf',
    );
  }

  static pw.Widget _sectionTitle(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        children: [
          pw.Container(
            width: 4,
            height: 13,
            decoration: pw.BoxDecoration(
              color: _gold,
              borderRadius: pw.BorderRadius.circular(2),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: _deepGreen,
            ),
          ),
        ],
      ),
    );
  }

  static pw.TableRow _customerRow(
      String label1,
      String value1,
      String label2,
      String value2,
      ) {
    return pw.TableRow(
      children: [
        _customerCell(label1, isLabel: true),
        _customerCell(value1),
        _customerCell(label2, isLabel: true),
        _customerCell(value2),
      ],
    );
  }

  static pw.Widget _customerCell(String text, {bool isLabel = false}) {
    return pw.Container(
      constraints: const pw.BoxConstraints(minHeight: 30),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      alignment: pw.Alignment.centerLeft,
      color: isLabel ? _lightGreen : _white,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: isLabel ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isLabel ? _deepGreen : _ink,
        ),
      ),
    );
  }

  static pw.TableRow _summaryRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 9, color: _ink),
          ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
        ),
      ],
    );
  }
}
