import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/models/trip_post.dart';
import 'package:taxi_app/core/models/trip_lifecycle.dart';
import 'package:taxi_app/core/models/user_reputation.dart';
import 'package:taxi_app/core/models/support_request.dart';
import 'package:taxi_app/core/models/support_message.dart';
import 'package:taxi_app/core/widgets/trip_lifecycle_panel.dart';
import 'package:taxi_app/core/widgets/reputation_summary.dart';
import 'package:taxi_app/core/widgets/trip_cancellation_button.dart';
import 'package:taxi_app/screens/support/support_screens.dart';
import 'package:taxi_app/screens/rating/rating_screen.dart';
import 'accepted_driver_trips_widget_test.dart' show acceptedTrip;

void main() {
  final now = DateTime.utc(2030,1,1);
  TripPost trip(String state) => TripPost.fromMap('trip-1',acceptedTrip().toFirestore()
    ..['status']=state ..['tripReference']='CT-260910-ABC234'
    ..['startAutoStartAt']=now.add(const Duration(minutes:3))
    ..['endAutoCompleteAt']=now.add(const Duration(minutes:30)));
  testWidgets('Participant controls, countdown and reference are visible', (tester) async {
    LifecycleAction? selected;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:TripLifecyclePanel(
      trip:trip('accepted'),uid:'driver-1',now:now,onAction:(a)=>selected=a))));
    expect(find.textContaining('CT-260910-ABC234'),findsOneWidget);
    await tester.tap(find.text('Start Trip')); expect(selected,LifecycleAction.requestStart);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:TripLifecyclePanel(
      trip:trip('start_requested'),uid:'creator-1',now:now,onAction:(a)=>selected=a))));
    expect(find.textContaining('Automatic start in 3:00'),findsOneWidget);
    await tester.tap(find.text('Confirm Start')); expect(selected,LifecycleAction.confirmStart);
    expect(find.text('End Trip'),findsNothing);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:TripLifecyclePanel(
      trip:trip('end_requested'),uid:'creator-1',now:now,onAction:(a)=>selected=a))));
    expect(find.textContaining('Automatic completion in 30:00'),findsOneWidget);
    await tester.tap(find.text('Confirm End')); expect(selected,LifecycleAction.confirmEnd);
  });
  testWidgets('No Stage 9 cancellation button after start request', (tester) async {
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:TripCancellationButton(trip:trip('in_progress'),byDriver:true))));
    expect(find.text('Cancel Trip'),findsNothing);
  });
  testWidgets('Reputation displays reviewed statistics without faking cancellation metrics', (tester) async {
    await tester.pumpWidget(const MaterialApp(home:Scaffold(body:ReputationSummary(
      reputation:UserReputation(completedTripsCount:48,averageRating:4.8,ratingsCount:31)))));
    expect(find.text('Completed trips: 48'),findsOneWidget);
    expect(find.text('Rating: 4.8 (31 reviews)'),findsOneWidget);
    expect(find.text('Cancellation rate: Not available'),findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home:Scaffold(body:ReputationSummary(
      creator:true,reputation:UserReputation(completedTripsCount:48,cancellationCount:2,cancellationRate:4)))));
    expect(find.text('Completed hires: 48'),findsOneWidget);
    expect(find.text('Cancellations: 2'),findsOneWidget);
    expect(find.text('Cancellation rate: 4%'),findsOneWidget);
  });
  testWidgets('Support pre-fills profile phone and requires contact/message fields', (tester) async {
    await tester.pumpWidget(MaterialApp(home:SupportFormScreen(loadProfile:() async => {'phoneNumber':'+94771234567'})));
    await tester.pumpAndSettle();
    final phone=find.widgetWithText(TextFormField,'Contact Number');
    expect(tester.widget<TextFormField>(phone).controller!.text,'+94771234567');
    expect(find.text('We may call this number regarding this request.'),findsOneWidget);
    await tester.enterText(phone,'');
    await tester.ensureVisible(find.text('Submit Request'));
    await tester.tap(find.text('Submit Request')); await tester.pump();
    expect(find.text('Phone number is required.'),findsOneWidget);
    await tester.enterText(phone,'+94779876543');
    expect(tester.widget<TextFormField>(phone).controller!.text,'+94779876543');
  });
  for (final creator in [true,false]) {
    testWidgets('Trip complaint attaches reference and role-specific categories: creator=$creator', (tester) async {
      await tester.pumpWidget(MaterialApp(home:SupportFormScreen(trip:trip('completed'),byCreator:creator,loadProfile:() async => {'phoneNumber':'+94771234567'})));
      await tester.pumpAndSettle();
      expect(find.text('CT-260910-ABC234'),findsOneWidget);
      final form=tester.widget<DropdownButton<String>>(find.descendant(of:find.byType(DropdownButtonFormField<String>),matching:find.byType(DropdownButton<String>)));
      expect(form.items!.map((e)=>e.value),creator?creatorComplaintCategories.keys:driverComplaintCategories.keys);
    });
  }
  testWidgets('My Support Requests renders the supplied own-request feed', (tester) async {
    const request=SupportRequest(id:'r',supportReference:'SUP-260910-ABC234',userId:'u',userRole:'driver',userName:'Driver',contactNumber:'+94771234567',category:'question',subject:'Help',message:'Question',status:'open');
    await tester.pumpWidget(MaterialApp(home:SupportRequestsScreen(requestsStream:Stream.value([request]))));
    await tester.pumpAndSettle();
    expect(find.text('My Support Requests'),findsOneWidget);
    expect(find.text('SUP-260910-ABC234'),findsOneWidget);
    expect(find.textContaining('Ask a Question'),findsOneWidget);
    expect(find.textContaining('open'),findsOneWidget);
  });
  testWidgets('Support conversation shows acknowledgement, staff reply and permits user reply', (tester) async {
    const request=SupportRequest(id:'r',supportReference:'SUP-260910-ABC234',userId:'u',userRole:'driver',userName:'Driver',contactNumber:'+94771234567',category:'complaint',subject:'Issue',message:'Original request',status:'open');
    String? reply;
    await tester.pumpWidget(MaterialApp(home:SupportThreadScreen(requestId:'r',requestStream:Stream.value(request),
      messagesStream:Stream.value([const SupportMessage(id:'m',senderId:'staff',senderRole:'admin',message:'We are reviewing your case.')]),onReply:(text) async => reply=text)));
    await tester.pumpAndSettle();
    expect(find.text(request.acknowledgement),findsOneWidget); expect(find.text('Support team'),findsOneWidget);
    expect(find.text('We are reviewing your case.'),findsOneWidget);
    final threadScroll = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    final replyInput = find.byKey(const Key('support_reply_field'));
    await tester.scrollUntilVisible(replyInput, 150, scrollable: threadScroll);
    expect(replyInput, findsOneWidget);
    await tester.enterText(replyInput, '  Thank you  ');
    // ListView builds children lazily; ensureVisible alone cannot find an unbuilt button.
    final sendReply = find.byKey(const Key('support_send_reply_button'));
    await tester.scrollUntilVisible(sendReply, 150, scrollable: threadScroll);
    expect(sendReply, findsOneWidget);
    await tester.tap(sendReply);
    await tester.pumpAndSettle();
    expect(reply,'Thank you');
  });
  testWidgets('Rating requires a written comment and submits independent selected stars', (tester) async {
    int? stars; String? comment;
    await tester.pumpWidget(MaterialApp(home:RatingScreen(trip:trip('completed'),byCreator:true,onSubmit:(s,c) async { stars=s; comment=c; })));
    await tester.ensureVisible(find.text('Submit Rating')); await tester.tap(find.text('Submit Rating')); await tester.pump();
    expect(find.text('Please write a review.'),findsOneWidget); expect(stars,isNull);
    await tester.enterText(find.widgetWithText(TextFormField,'Written review'),'  Comfortable trip  ');
    await tester.ensureVisible(find.text('Submit Rating')); await tester.tap(find.text('Submit Rating')); await tester.pumpAndSettle();
    expect(stars,5); expect(comment,'Comfortable trip');
  });
}
