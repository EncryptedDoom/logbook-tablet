/// The public half of the activation key, written by
/// `dart run tool/activate.dart init`. It can check an activation code but
/// cannot make one, so it is safe to ship inside the app.
library;

const activationPublicKey = <int>[
  132, 8, 146, 77, 107, 189, 165, 142,
  77, 111, 231, 128, 184, 196, 207, 140,
  245, 145, 239, 208, 122, 207, 1, 30,
  161, 40, 186, 107, 128, 156, 126, 212,
];
