// Pendant la déconnexion (12 s au plus) : l'espace chauffeur ne se touche
// plus, et le chauffeur voit que ça avance.
import 'package:flutter/material.dart';

import '../theme/couleurs_taama.dart';

class VoileDeconnexion extends StatelessWidget {
  const VoileDeconnexion({super.key});

  @override
  Widget build(BuildContext context) {
    return const AbsorbPointer(
      child: ColoredBox(
        color: Colors.black38,
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: CouleursTaama.blanc,
                borderRadius: BorderRadius.all(Radius.circular(16)),
                boxShadow: [BoxShadow(color: CouleursTaama.ombre, blurRadius: 24, offset: Offset(0, 8))],
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: CouleursTaama.terreCuite),
                    ),
                    SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        'Déconnexion…',
                        style: TextStyle(
                          color: CouleursTaama.indigo,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
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
