String authErrorMessage(String code) => switch (code) {
      'email-already-in-use' => 'Ese correo ya tiene una cuenta.',
      'invalid-email' => 'El correo no tiene un formato válido.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' =>
        'El correo o la contraseña no son correctos.',
      'weak-password' => 'Elige una contraseña más segura.',
      'network-request-failed' =>
        'Revisa tu conexión a internet e inténtalo de nuevo.',
      'too-many-requests' =>
        'Hubo demasiados intentos. Espera un momento y vuelve a probar.',
      'user-disabled' =>
        'Esta cuenta está deshabilitada. Contacta con soporte.',
      _ => 'No se pudo completar la autenticación. Inténtalo de nuevo.',
    };
