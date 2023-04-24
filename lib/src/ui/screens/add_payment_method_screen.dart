import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:stripe_sdk/src/ui/stores/payment_method_store.dart';

import '../../models/card.dart';
import '../../stripe.dart';
import '../models.dart';
import '../progress_bar.dart';
import '../stripe_ui.dart';
import '../widgets/card_form.dart';

/// A screen that collects, creates and attaches a payment method to a stripe customer.
///
/// Payment methods can be created with and without a Setup Intent. Using a Setup Intent is highly recommended.
///
class AddPaymentMethodScreen extends StatefulWidget {
  final Stripe stripe;

  /// Used to create a setup intent when required.
  final createSetupIntent = StripeUiOptions.createSetupIntent;

  /// The payment method store used to manage payment methods.
  final PaymentMethodStore paymentMethodStore;

  /// Custom Title for the screen
  final String title;
  static const String _defaultTitle = 'Add payment method';
  final double? viewPadding;
  final CardForm? form;

  static Route<String?> route(
      {PaymentMethodStore? paymentMethodStore, Stripe? stripe, CardForm? form, String title = _defaultTitle,
        double? viewPadding}) {
    return MaterialPageRoute(
      builder: (context) => AddPaymentMethodScreen(
        paymentMethodStore: paymentMethodStore ?? PaymentMethodStore.instance,
        stripe: stripe ?? Stripe.instance,
        title: title,
          viewPadding: viewPadding,
          form: form
      ),
    );
  }

  /// Add a payment method using a Stripe Setup Intent
  AddPaymentMethodScreen({Key? key, required this.paymentMethodStore, required this.stripe, this.title = _defaultTitle, this.viewPadding, this.form})
      : super(key: key);

  @override
  _AddPaymentMethodScreenState createState() => _AddPaymentMethodScreenState();
}

class _AddPaymentMethodScreenState extends State<AddPaymentMethodScreen> {
  Future<IntentClientSecret>? setupIntentFuture;
  CardForm form = CardForm();

  @override
  void initState() {
    if (widget.createSetupIntent != null) setupIntentFuture = widget.createSetupIntent!();
    form = widget.form!;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(
            onPressed: () => {Navigator.maybePop(context)},
            icon: const Icon(
              Icons.arrow_back,
              color: Colors.white,
            ),
          ),
        ),
        body: Container(
          height: MediaQuery.of(context).size.height,
          padding: EdgeInsets.symmetric(horizontal: widget.viewPadding!),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              form,
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 25),
                  child: ConstrainedBox(
                    constraints: BoxConstraints.tightFor(
                        width: MediaQuery.of(context).size.width, height: 50),
                    child: ElevatedButton(
                      child: const Text(
                        'Add Card',
                        style: TextStyle(
                            color: Color(0xffffffff),
                            // fontFamily: headingText,
                            fontWeight: FontWeight.w600,
                            fontSize: 18),
                      ),
                      style: ButtonStyle(
                        foregroundColor:
                        MaterialStateProperty.all<Color>(Color(0xff223039)),
                        backgroundColor:
                        MaterialStateProperty.all<Color>(Color(0xff223039)),
                        shape:
                        MaterialStateProperty.all<RoundedRectangleBorder>(
                            const RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.all(Radius.circular(10)),
                                side:
                                BorderSide(color: Colors.transparent))),
                      ),
                      onPressed: () async {
                        final formState = form.formKey.currentState;
                        if (formState?.validate() ?? false) {
                          formState!.save();
                          await _tryCreatePaymentMethod(context, form.card);
                        }
                      },
                    ),
                  ),
                ),
              ),

              if (StripeUiOptions.showTestPaymentMethods)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Wrap(
                    children: [
                      _createTestCardButton("4242424242424242"),
                      _createTestCardButton("4000000000003220"),
                      _createTestCardButton("4000000000003063"),
                      _createTestCardButton("4000008400001629"),
                      _createTestCardButton("4000008400001280"),
                      _createTestCardButton("4000000000003055"),
                      _createTestCardButton("4000000000003097"),
                      _createTestCardButton("378282246310005"),
                    ],
                  ),
                )
            ],
          ),
        ),

                    );
  }

  Widget _createTestCardButton(String number) {
    return OutlinedButton(
        child: Text(number.substring(number.length - 4)),
        onPressed: () =>
            _tryCreatePaymentMethod(context, StripeCard(number: number, cvc: "123", expMonth: 1, expYear: 2030)));
  }

  Future<void> _tryCreatePaymentMethod(BuildContext context, StripeCard cardData) async {
    FocusManager.instance.primaryFocus!.unfocus();
    showProgressDialog(context);
    try {
      await _createPaymentMethod(cardData, context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _createPaymentMethod(StripeCard cardData, BuildContext context) async {
    showProgressDialog(context);
    var paymentMethod;
    try {
      paymentMethod = await widget.stripe.api.createPaymentMethodFromCard(cardData);
    } on Exception catch (e) {
      SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
        Navigator.maybePop(context, false);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
      debugPrint(e.toString());
    }
    if (setupIntentFuture != null) {
      final initialSetupIntent =
          await setupIntentFuture!.timeout(const Duration(seconds: 10)).whenComplete(() => hideProgressDialog(context));
      try {
        final confirmedSetupIntent = await widget.stripe
            .confirmSetupIntent(initialSetupIntent.clientSecret, paymentMethod['id'], context: context);
        if (confirmedSetupIntent['status'] == 'succeeded') {
          debugPrint("1");
          /// A new payment method has been attached, so refresh the store.
          await widget.paymentMethodStore.refresh();
          debugPrint("2");
          hideProgressDialog(context);
          debugPrint("3");
          Navigator.pop(context, jsonEncode(paymentMethod));
          debugPrint("4");
          return;
        } else {
          Map<String, dynamic> errorData = {
            'error': true,
            'message': 'Authentication failed'
          };
          debugPrint("5");
          Navigator.pop(context, errorData);
          debugPrint("6");
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text("Authentication failed, please try again.")));
        }
      }  catch (e) {
        debugPrint("7");
        SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
          Navigator.maybePop(context, false);
        });
        debugPrint("ena errr9r da please ");
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
        debugPrint("ena errr9r ");
      }
    } else {
      paymentMethod = await (widget.paymentMethodStore.attachPaymentMethod(paymentMethod['id']))
          .whenComplete(() => hideProgressDialog(context));
      Navigator.pop(context, paymentMethod['id']);
    }
  }
}
