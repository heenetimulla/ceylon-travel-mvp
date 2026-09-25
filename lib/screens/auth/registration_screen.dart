import '../../core/widgets/app_components.dart';
import '../../app/app_text_styles.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/enums/account_type.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/bid_service.dart';
import '../../core/validation/registration_validation.dart';
import 'registration_application_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({
    super.key,
    this.initialAccountType = AccountType.tourist,
    this.resumeAuthenticated = false,
  });

  final AccountType initialAccountType;
  final bool resumeAuthenticated;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final TextEditingController cityController = TextEditingController();
  String? vehicleType;
  final TextEditingController vehicleNumberController = TextEditingController();
  final TextEditingController operatingAreaController = TextEditingController();
  final TextEditingController availableAreasController =
      TextEditingController();
  AuthService? _authService;
  FirebaseFirestore? _firestore;
  String? _createdUid;

  late AccountType selectedAccountType;
  bool isRegistering = false;

  bool get isDriver => selectedAccountType == AccountType.driver;

  AuthService get authService => _authService ??= AuthService();

  FirebaseFirestore get firestore => _firestore ??= FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    if (widget.resumeAuthenticated) {
      _createdUid = authService.currentUser?.uid;
      emailController.text = authService.currentUser?.email ?? '';
    }
    selectedAccountType = widget.initialAccountType == AccountType.driver
        ? AccountType.driver
        : AccountType.tourist;
  }

  @override
  void dispose() {
    fullNameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    cityController.dispose();
    vehicleNumberController.dispose();
    operatingAreaController.dispose();
    availableAreasController.dispose();
    super.dispose();
  }

  void _selectAccountType(AccountType accountType) {
    setState(() {
      selectedAccountType = accountType;
    });
  }

  Future<void> _createAccount() async {
    if (isRegistering) return;

    final String? validationError = _validateRegistration();
    if (validationError != null) {
      _showRegistrationError(validationError);
      return;
    }

    setState(() {
      isRegistering = true;
    });

    try {
      if (_createdUid == null) {
        final credential = await authService.registerWithEmailAndPassword(
          email: emailController.text,
          password: passwordController.text,
        );
        _createdUid = credential.user?.uid;
      }
      final String? uid = _createdUid;

      if (uid == null || authService.currentUser?.uid != uid) {
        _showRegistrationError(
          'Registration could not be completed. Please try again.',
        );
        return;
      }

      final ref = firestore.collection('users').doc(uid);
      final existing = await ref.get(const GetOptions(source: Source.server));
      if (!existing.exists) { await ref.set(_buildUserDocument(uid)); }

      if (!mounted) return;

      _openApplication(uid);
    } on AuthServiceException catch (exception) {
      _showRegistrationError(exception.message);
    } on FirebaseException {
      _showRegistrationError(
        'Your account was created, but your profile could not be saved. Please try again.',
      );
    } catch (_) {
      _showRegistrationError('Registration failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          isRegistering = false;
        });
      }
    }
  }

  String? _validateRegistration() {
    if (_isBlank(fullNameController)) {
      return 'Full name is required.';
    }
    final phoneError = validateRegistrationPhone(phoneController.text);
    if (phoneError != null) return phoneError;
    if (_isBlank(emailController)) {
      return 'Email is required.';
    }
    if (!_isValidEmail(emailController.text.trim())) {
      return 'Enter a valid email address.';
    }
    if (_createdUid == null && _isBlank(passwordController)) {
      return 'Password is required.';
    }
    if (_createdUid == null && _isBlank(confirmPasswordController)) {
      return 'Confirm password is required.';
    }
    if (_createdUid == null && passwordController.text != confirmPasswordController.text) {
      return 'Passwords do not match.';
    }
    if (_isBlank(cityController)) {
      return 'City / District is required.';
    }
    if (isDriver) {
      if (!BidService.vehicleTypes.contains(vehicleType)) {
        return 'Vehicle type is required.';
      }
      if (_isBlank(vehicleNumberController)) {
        return 'Vehicle number is required.';
      }
      if (_isBlank(operatingAreaController)) {
        return 'Operating area is required.';
      }
      if (_isBlank(availableAreasController)) {
        return 'Available areas are required.';
      }
    }

    return null;
  }

  bool _isBlank(TextEditingController controller) {
    return controller.text.trim().isEmpty;
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  Map<String, Object?> _buildUserDocument(String uid) {
    final FieldValue timestamp = FieldValue.serverTimestamp();
    final Map<String, Object?> userDocument = {
      'uid': uid,
      'fullName': fullNameController.text.trim(),
      'email': authService.currentUser?.email ?? emailController.text.trim(),
      'phoneNumber': phoneController.text.trim(),
      'city': cityController.text.trim(),
      'accountType': isDriver ? 'driver' : 'tourist',
      'profilePhotoPath': null,
      'status': 'active',
      'registrationStatus': 'draft',
      'accountStatus': 'pending_approval',
      'applicationRevision': 0,
      'averageRating': 0,
      'ratingsCount': 0,
      'ratingStarsTotal': 0,
      'cancellationCount': 0,
      'completedTripsCount': 0,
      'cancelledTripsCount': 0,
      'cancellationRate': 0,
      'createdAt': timestamp,
      'updatedAt': timestamp,
    };

    if (isDriver) {
      userDocument.addAll({
        'vehicleType': vehicleType,
        'vehicleNumber': vehicleNumberController.text.trim(),
        'operatingArea': operatingAreaController.text.trim(),
        'availableAreas': availableAreasController.text.trim(),
        'verification': {
          'status': 'pending',
          'submittedAt': timestamp,
          'reviewedAt': null,
          'reviewedBy': null,
          'rejectionReason': null,
        },
      });
    }

    return userDocument;
  }

  void _showRegistrationError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openApplication(String uid) {
    passwordController.clear(); confirmPasswordController.clear();
    Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => RegistrationApplicationScreen(uid: uid)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppPageAppBar(contentWidth: 620, title: const Text('Register')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: AbsorbPointer(
            absorbing: isRegistering,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: AppInfoCard(
                  children: [
                    const AppBrandHeader(),
                    const Text(
                      'Start your registration application',
                      style: AppTextStyles.title,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose your account type and enter your details. Next, upload identity documents and accept the guidelines. Creating login credentials does not approve your account.',
                      style: AppTextStyles.secondary,
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      enabled: _createdUid == null,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_createdUid == null) TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_createdUid == null) TextField(
                      controller: confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                        prefixIcon: Icon(Icons.lock_reset_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: cityController,
                      decoration: const InputDecoration(
                        labelText: 'City / District',
                        prefixIcon: Icon(Icons.location_city_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Account type selector',
                      style: AppTextStyles.cardTitle,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ChoiceChip(
                          key: const Key('touristAccountTypeChip'),
                          label: const Text('Tourist/User'),
                          selected: selectedAccountType == AccountType.tourist,
                          onSelected: (_) =>
                              _selectAccountType(AccountType.tourist),
                        ),
                        ChoiceChip(
                          key: const Key('driverAccountTypeChip'),
                          label: const Text('Driver'),
                          selected: selectedAccountType == AccountType.driver,
                          onSelected: (_) =>
                              _selectAccountType(AccountType.driver),
                        ),
                      ],
                    ),
                    if (isDriver) ...[
                      const SizedBox(height: 22),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: vehicleType,
                        items: [
                          for (final type in BidService.vehicleTypes)
                            DropdownMenuItem(value: type, child: Text(type)),
                        ],
                        onChanged: isRegistering
                            ? null
                            : (value) => setState(() => vehicleType = value),
                        decoration: const InputDecoration(
                          labelText: 'Vehicle type',
                          helperText:
                              'Your primary vehicle. You may offer a different vehicle for each bid.',
                          helperMaxLines: 2,
                          prefixIcon: Icon(Icons.directions_car_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: vehicleNumberController,
                        decoration: const InputDecoration(
                          labelText: 'Vehicle number',
                          prefixIcon: Icon(Icons.confirmation_number_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: operatingAreaController,
                        decoration: const InputDecoration(
                          labelText: 'Operating area',
                          prefixIcon: Icon(Icons.map_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: availableAreasController,
                        decoration: const InputDecoration(
                          labelText: 'Available areas',
                          prefixIcon: Icon(Icons.route_outlined),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('createAccountButton'),
                        onPressed: isRegistering ? null : _createAccount,
                        child: isRegistering
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Continue to identity & documents'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
