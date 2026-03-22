import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';

class DevelopersScreen extends StatelessWidget {
  const DevelopersScreen({super.key});

  final Color primaryYellow = const Color(0xFFFFD166);
  final Color backgroundGrey = const Color(0xFFF0F2F5);
  final Color textBlack = const Color(0xFF1A1D20);
  final Color textGrey = const Color(0xFF6C757D);

  @override
  Widget build(BuildContext context) {
    // List of 6 Developers with unique soft background colors
    final List<Map<String, dynamic>> devs = [
      {
        "name": "Devyansh Kumar",
        "role": "Lead & UI/UX",
        "image": "assets/devs/lead.png",
        "color": primaryYellow.withOpacity(0.4), // Theme Yellow
        "ig": "https://www.instagram.com/devyansh_iitp/",
        "linkedin": "https://www.linkedin.com/in/devyanshkumar/",
      },
      {
        "name": "Aditya Kumar Lal",
        "role": "Full Stack Developer",
        "image": "assets/devs/dev.png",
        "color": const Color.fromARGB(255, 226, 226, 233), // Theme Soft Grey
        "ig": "https://instagram.com/john",
        "linkedin": "https://linkedin.com/in/john",
      },
      {
        "name": "Sameer Sonkar",
        "role": "Frontend",
        "image": "assets/devs/dev.png",
        "color": const Color(0xFFFFE8D6), // Soft Peach
        "ig": "https://instagram.com/jane",
        "linkedin": "https://linkedin.com/in/jane",
      },
      {
        "name": "Barvadiya Yash Jigneshbhai",
        "role": "Database",
        "image": "assets/devs/dev.png",
        "color": const Color(0xFFD3D6DA), // Theme Darker Grey
        "ig": "https://instagram.com/alex",
        "linkedin": "https://linkedin.com/in/alex",
      },
      {
        "name": "Ved Tejani",
        "role": "Cloud Architect",
        "image": "assets/devs/dev.png",
        "color": const Color(0xFFE2ECE9), // Soft Mint
        "ig": "https://instagram.com/sam",
        "linkedin": "https://linkedin.com/in/sam",
      },
      {
        "name": "Rajan Raj",
        "role": "Tester",
        "image": "assets/devs/dev.png",
        "color": const Color(0xFFFDE2E4), // Soft Pink
        "ig": "https://instagram.com/chris",
        "linkedin": "https://linkedin.com/in/chris",
      },
    ];

    return Scaffold(
      backgroundColor: backgroundGrey,
      appBar: AppBar(
        backgroundColor: backgroundGrey,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textBlack),
        title: Text(
          "Meet the Developer Teams",
          style: TextStyle(
            color: textBlack,
            fontWeight: 
            FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            // Grid layout for 2-in-a-row Pill Cards
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: devs.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,           // 2 items per row
                crossAxisSpacing: 16,        // Horizontal space between cards
                mainAxisSpacing: 24,         // Vertical space between cards
                childAspectRatio: 0.55,      // Makes the cards tall (Pill shape)
              ),
              itemBuilder: (context, index) {
                final dev = devs[index];
                return _buildPillCard(
                  name: dev["name"],
                  role: dev["role"],
                  imagePath: dev["image"],
                  bgColor: dev["color"],
                  igUrl: dev["ig"],
                  linkedinUrl: dev["linkedin"],
                )
                // Staggered animation: each card fades in slightly after the previous one
                .animate(delay: (100 * index).ms)
                .fadeIn(duration: 500.ms)
                .slideY(begin: 0.1, end: 0);
              },
            ),
            
            const SizedBox(height: 40), // Bottom padding
          ],
        ),
      ),
    );
  }

  // --- The Pill Card Design ---
  Widget _buildPillCard({
    required String name,
    required String role,
    required String imagePath,
    required Color bgColor,
    required String igUrl,
    required String linkedinUrl,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(100), // Makes it a perfect pill
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            // 1. Transparent Person PNG (Anchored to the bottom)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Image.asset(
                imagePath,
                fit: BoxFit.fitWidth,
                alignment: Alignment.bottomCenter,
                errorBuilder: (context, error, stackTrace) => 
                  Icon(Icons.person, size: 80, color: Colors.white.withOpacity(0.5)),
              ),
            ),
            
            // 2. Text & Social Icons (Anchored to the top)
            Padding(
              padding: const EdgeInsets.only(top: 32, left: 12, right: 12),
              child: Column(
                children: [
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15, 
                      fontWeight: FontWeight.w900, 
                      color: textBlack, 
                      height: 1.1
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    role,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11, 
                      fontWeight: FontWeight.w800, 
                      color: textBlack.withOpacity(0.6)
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Social Buttons Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildSocialBtn(Icons.camera_alt_outlined, igUrl),
                      const SizedBox(width: 8),
                      _buildSocialBtn(Icons.work_outline_rounded, linkedinUrl),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Glassmorphic Social Button ---
  Widget _buildSocialBtn(IconData icon, String url) {
    return InkWell(
      onTap: () async {
        final Uri parsedUrl = Uri.parse(url);
        if (!await launchUrl(parsedUrl, mode: LaunchMode.externalApplication)) {
          debugPrint("Could not launch $url");
        }
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.6), // Frosted white over the pastel background
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: textBlack),
      ),
    );
  }
}