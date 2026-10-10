# Elevate Frontend

> The active app is the native SwiftUI rewrite in [`ios-native/`](ios-native/). The Expo app at the repository root is kept as a legacy reference.

**Elevate** is a modern mobile app designed to reimagine the Skyward gradebook experience. Built with **React Native** and styled with **NativeWind**, it empowers students to track grades, manage assignments, and plan ahead with calendar sync and GPA insights.

🔗 **Backend Repo**: [Elevate-Backend](https://github.com/Zw96042/Elevate-Backend)  
📋 **Project Board**: [GitHub Project Tracker](https://github.com/users/Zw96042/projects/2)

---

## 🚀 Project Vision

Elevate provides a cleaner, more useful, and student-focused alternative to Skyward. Core features include:

- GPA calculator
- Calendar integration (Google/Apple)
- Class and assignment tracking
- Inbox and message views
- Secure authentication flow

---

## 🎯 Project Takeaways

-  Build a performant mobile app with **React Native**
-  Use **Expo Router** and navigation for modern routing
-  Style consistently with **NativeWind (Tailwind for RN)**
-  Connect securely to Elevate’s backend services
-  Organize UI components and logic in a scalable file structure
-  Track development with a public project board

---

## 🛠️ Tech Stack

- **React Native** (v0.79.2)
- **Expo** (with custom dev client)
- **Expo Router** for navigation
- **NativeWind** for Tailwind-style styling
- **Axios** for API requests
- **React Navigation** suite
- Calendar and biometric support via **expo modules**

---

## 📂 File Structure
```
Elevate-Frontend/
├── app/
│   ├── (tabs)/              # Tab layout and views (Assignments, Inbox, Profile)
│   ├── assignments/         # Assignment-specific pages
│   ├── classes/             # Class-specific pages
│   ├── inbox/               # Inbox-specific message pages
│   └── globals.css          # Global styles
├── assets/                  # Fonts, images, icons
├── components/              # UI components (Cards, etc.)
├── constants/               # Static values/config
├── interfaces/              # Shared TypeScript types
├── lib/                     # API handlers and auth logic
├── types/                   # Type helpers
├── utils/                   # Utility functions (e.g., formatClassName)
└── app.config.js / package.json
```
---

## ✅ Current Development

Check out features currently in progress, planned, or completed here:  
🔗 [Elevate Project Board](https://github.com/users/Zw96042/projects/2)

---

## 🐛 Bug Reports & Suggestions

If you encounter any issues, have feedback, or want to suggest improvements:

Please open an issue on [this repository](https://github.com/Zw96042/Elevate-Frontend/issues)

Currently this app only supports a very limited amount of school districts. To make a request to add a school district, please filll out [this](https://docs.google.com/forms/d/e/1FAIpQLSdqtqDEwLQY03KHS_LZDpjOjTcP_j8MCIizaMRMHTS6T5tOzQ/viewform?usp=dialog) form.

---

## 📬 Contact

Maintained by Zachary Wilson  
📧 [zach.wilson.atx@gmail.com](mailto:zach.wilson.atx@gmail.com)