📱 Advanced Android Camera & Photo Editor App
সম্পূর্ণ ফিচার ও ডেভেলপমেন্ট প্রম্পট
🔷 Project Overview

আমি একটি আধুনিক, দ্রুতগতির এবং নির্ভুল Android Camera & Photo Processing Application তৈরি করতে চাই।

অ্যাপটির মাধ্যমে ব্যবহারকারী ক্যামেরা দিয়ে ছবি তুলতে, গ্যালারি থেকে ছবি নির্বাচন করতে এবং ছবিকে বিভিন্ন পদ্ধতিতে প্রসেস করতে পারবেন।

অ্যাপটি সাধারণ ফটোগ্রাফি, শিক্ষাপ্রতিষ্ঠানের কাজ, প্রিন্টিং, অনলাইন আবেদনপত্র এবং বাংলাদেশের NID/Passport/সরকারি ফরমের জন্য ছবি প্রস্তুত করার কাজে ব্যবহারযোগ্য হবে।

অ্যাপটি Android ফোনে দ্রুত কাজ করবে এবং ব্যবহারকারীর জন্য সহজ, আধুনিক ও পেশাদার UI প্রদান করবে।

১️⃣ Camera System (ক্যামেরা সিস্টেম)

অ্যাপটিতে নিম্নলিখিত ক্যামেরা ফিচার থাকতে হবে:

📷 Basic Camera
Front Camera
Back Camera
Camera Switch
Photo Capture
Video Capture (ঐচ্ছিক)
Auto Focus
Tap to Focus
Focus Lock
Exposure Adjustment
Flash On / Off / Auto
Camera Zoom
Digital Zoom
Grid Lines
Timer: 3 / 5 / 10 seconds
Shutter Sound Control (ডিভাইস ও সিস্টেম সীমাবদ্ধতা মেনে)
Camera Resolution Selection
Aspect Ratio Selection:
1:1
3:4
4:3
16:9
Full Screen
🔧 Advanced Camera
Auto Exposure
White Balance (যদি ডিভাইস সমর্থন করে)
ISO Control (যদি Camera2 API সমর্থন করে)
Shutter Speed (সমর্থিত ডিভাইসে)
Manual Focus
RAW Capture (সমর্থিত ডিভাইসে)
HDR (সমর্থিত ডিভাইসে)
Low Light Optimization
Camera Capability Detection

গুরুত্বপূর্ণ: যেসব ফিচার ফোনের হার্ডওয়্যার বা Android Camera API সমর্থন করে না, সেগুলো স্বয়ংক্রিয়ভাবে Disable বা Hide করতে হবে।

২️⃣ Image Crop System (ছবি ক্রপ)

ছবি তোলার পর বা গ্যালারি থেকে ছবি নির্বাচনের পর ক্রপ করার সুবিধা থাকতে হবে।

✂️ Crop Features
Free Crop
Fixed Ratio Crop
Square Crop
Portrait Crop
Landscape Crop
Custom Width & Height Crop
Drag to Crop
Crop Preview
Rotate Before Crop
Crop Reset
Crop Undo / Redo
High-Quality Cropped Image Export
📐 Preset Crop Ratios
1:1
3:4
4:3
16:9
2:3
Custom Ratio

ক্রপ করার সময় ছবির গুণমান যতটা সম্ভব সংরক্ষণ করতে হবে।

৩️⃣ Image Resize System (ছবি রিসাইজ)

ব্যবহারকারী ছবির Width এবং Height নির্ধারণ করে রিসাইজ করতে পারবেন।

📏 Resize Features
Custom Width
Custom Height
Maintain Aspect Ratio
Lock / Unlock Ratio
Resize by Percentage
Resize by Pixels
Resize by Centimeters (DPI-ভিত্তিক)
Resize by Inches
Preset Image Sizes
Preview Before Export
উদাহরণ:
300 × 300 px
600 × 600 px
Passport Photo Size
Custom Government Application Size
Print Size

সতর্কতা: Pixels, Inches এবং Centimeters-এর মধ্যে রূপান্তরের সময় DPI সঠিকভাবে পরিচালনা করতে হবে।

৪️⃣ Image Compression System (ছবির সাইজ কমানো)

ছবির গুণমান বজায় রেখে ফাইলের সাইজ কমানোর ব্যবস্থা থাকতে হবে।

🗜️ Compression Features
JPEG Compression
PNG Export
WebP Export (সমর্থিত হলে)
Quality Slider: 10–100
Target File Size
Compress to KB
Compress to MB
Preview Before Compression
Original vs Compressed Size
Estimated Output Size
Batch Compression
উদাহরণ:
ছবির সাইজ 2 MB থেকে 200 KB করা
500 KB-এর মধ্যে ছবি প্রস্তুত করা
নির্দিষ্ট ফাইল সাইজ অনুযায়ী Quality Adjust করা

Target File Size Compression-এর জন্য iterative compression অথবা উপযুক্ত image encoding পদ্ধতি ব্যবহার করতে হবে।

৫️⃣ Background Processing System

ছবির ব্যাকগ্রাউন্ড পরিবর্তন ও প্রস্তুত করার সুবিধা থাকতে পারে।

🖼️ Features
Background Removal (ঐচ্ছিক AI)
White Background
Blue Background
Custom Background Color
Transparent Background (PNG)
Background Preview
Edge Refinement
Hair/Boundary Preservation
Manual Eraser
Background Replacement

AI Background Removal ব্যবহারের ক্ষেত্রে অনলাইন API-এর পাশাপাশি সম্ভব হলে অন-ডিভাইস প্রসেসিং বিবেচনা করতে হবে।

৬️⃣ Photo Enhancement System

ছবির মান উন্নত করার জন্য:

Brightness
Contrast
Saturation
Sharpness
Exposure
Highlights
Shadows
Temperature
Tint
Blur
Denoise
Auto Enhance
Original Image Restore
Before / After Preview

ছবিকে অতিরিক্ত প্রসেস করে যেন অস্বাভাবিক বা বিকৃত না করা হয়।

৭️⃣ Rotation & Alignment System
Rotate 90° / 180° / 270°
Free Rotation
Horizontal Flip
Vertical Flip
Auto Orientation
Straighten Image
Perspective Correction
Document Alignment

ডকুমেন্ট বা আবেদনপত্রের ছবি সোজা করার জন্য Perspective Correction ব্যবহার করা যাবে।

৮️⃣ Passport / NID / Government Photo System

বাংলাদেশের সরকারি ও অনলাইন আবেদনপত্রের জন্য আলাদা Photo Preparation Module তৈরি করতে হবে।

🇧🇩 Features
Passport Photo Preparation
NID Photo Preparation
Visa Photo Preparation
Job Application Photo
Educational Institution Photo
Custom Government Photo Presets
Custom Width & Height
Background Color Selection
Face Position Guide
Headroom Guide
Print Sheet Generation
Multiple Photos on One Page
উদাহরণ:
নির্দিষ্ট Pixel Size
নির্দিষ্ট KB Limit
White Background
নির্দিষ্ট Ratio
Photo Sheet তৈরি

প্রতিটি সরকারি প্রতিষ্ঠানের ছবির মাপ, ব্যাকগ্রাউন্ড এবং ফাইল সাইজের নিয়ম আলাদা হতে পারে। তাই ব্যবহারকারী যেন কাস্টম Preset তৈরি করতে পারেন।

৯️⃣ Face Detection & Position Guide

ক্যামেরা বা ছবিতে মুখ শনাক্ত করার সুবিধা থাকতে পারে।

Features
Face Detection
Face Centering
Face Position Guide
Multiple Face Detection
Face Bounding Box
Headroom Estimation
Automatic Crop Suggestion
Face Alignment

মুখ শনাক্তকরণ শুধু সহায়ক নির্দেশনা হিসেবে কাজ করবে। ব্যবহারকারীর অনুমতি ছাড়া ছবি আপলোড করা যাবে না।

🔟 Document Scanner System

সাধারণ কাগজপত্র স্ক্যান করার জন্য:

Document Edge Detection
Auto Crop
Perspective Correction
Scan as Image
Scan as PDF
Multi-Page PDF
Black & White Mode
Grayscale Mode
Color Document Mode
Shadow Reduction
Document Enhancement
1️⃣1️⃣ Batch Processing System

একসঙ্গে অনেক ছবি প্রসেস করার ব্যবস্থা রাখতে হবে।

Features
Multiple Image Selection
Batch Resize
Batch Crop
Batch Compression
Batch Format Conversion
Batch Rename
Batch Background Processing
Batch Export
Progress Indicator
Cancel Processing
Error Reporting

উদাহরণ:

একসঙ্গে ৫০টি ছবি নির্বাচন করে:

300 × 300 px করা
200 KB-এর মধ্যে রাখা
JPEG-এ রূপান্তর করা
নির্দিষ্ট ফোল্ডারে সংরক্ষণ করা
1️⃣2️⃣ Image Format Support

অ্যাপটি নিম্নলিখিত ফরম্যাট সমর্থন করবে:

Format	ব্যবহার
JPEG / JPG	সাধারণ ছবি ও আবেদনপত্র
PNG	স্বচ্ছ ব্যাকগ্রাউন্ড ও গ্রাফিক্স
WebP	ছোট ফাইল সাইজ
HEIC	ডিভাইস সমর্থন করলে
PDF	ডকুমেন্ট স্ক্যান

ফরম্যাট কনভার্সনের সময় ছবি বিকৃত হওয়া এবং অপ্রয়োজনীয় Metadata সংরক্ষণ এড়াতে হবে।

1️⃣3️⃣ Print Layout System

ছবি প্রিন্ট করার জন্য:

A4 Paper
4R Photo Paper
Custom Paper Size
Multiple Photos per Page
Adjustable Spacing
Custom Margins
Portrait / Landscape
Print Preview
PDF Export
Image Sheet Export
DPI Settings

উদাহরণ:

একটি A4 পৃষ্ঠায় একাধিক Passport Photo সাজিয়ে প্রিন্ট করার ব্যবস্থা।

1️⃣4️⃣ File Management System
Features
Save to Gallery
Custom Folder Selection
File Naming
Auto File Naming
Rename Image
Delete Image
Share Image
Export Image
Export History
Recent Files
Storage Permission Handling

ফাইল সংরক্ষণের ক্ষেত্রে Android-এর Scoped Storage এবং আধুনিক Permission পদ্ধতি অনুসরণ করতে হবে।

1️⃣5️⃣ Modern UI / UX Design

অ্যাপটির ডিজাইন হবে আধুনিক, সহজ এবং দ্রুত ব্যবহারযোগ্য।

UI Features
Material 3 Design
Light Mode
Dark Mode
Responsive Layout
Bottom Navigation
Camera Preview Screen
Editing Workspace
Image Preview
Undo / Redo
Clear Error Messages
Loading Indicator
Progress Bar
Accessibility Support
Bengali / English Language Support
প্রধান স্ক্রিন:
Home
Camera
Gallery
Photo Editor
Resize & Compress
Document Scanner
Batch Processing
Settings
1️⃣6️⃣ Performance & Security

অ্যাপটি অবশ্যই:

দ্রুত ছবি প্রসেস করবে
বড় ছবিতে Memory Management করবে
Out-of-Memory Error প্রতিরোধ করবে
Background Processing ব্যবহার করবে
ANR প্রতিরোধ করবে
Crash Handling করবে
EXIF Orientation সঠিকভাবে পরিচালনা করবে
Original Image সংরক্ষণ করবে
ব্যবহারকারীর অনুমতি ছাড়া ছবি আপলোড করবে না
অপ্রয়োজনীয় ইন্টারনেট Permission ব্যবহার করবে না

বিশেষভাবে Android-এর বড় ছবি প্রসেসিংয়ের ক্ষেত্রে Bitmap Memory Management অত্যন্ত গুরুত্বপূর্ণ।

1️⃣7️⃣ Technology Stack

AI Developer-কে নিম্নলিখিত প্রযুক্তি বিবেচনা করতে বলুন:

Recommended
Kotlin
Android Studio
Jetpack Compose অথবা XML
CameraX
Android Photo Picker
Kotlin Coroutines
ViewModel
Room Database (যদি History দরকার হয়)
ML Kit (প্রয়োজন অনুযায়ী)
Coil অথবা উপযুক্ত Image Loading Library
Modern Android Storage APIs
Architecture
MVVM
Clean Architecture (প্রয়োজন অনুযায়ী)
Modular Code Structure
Reusable Image Processing Engine
Separate Camera & Editor Modules
1️⃣8️⃣ Error Handling System

নিম্নলিখিত বিষয়গুলোর জন্য সঠিক Error Handling থাকতে হবে:

Camera Permission Denied
Gallery Access Denied
Unsupported Image Format
Image Too Large
Insufficient Storage
Export Failed
Compression Target Not Achieved
Camera Hardware Unavailable
Invalid Width / Height
Invalid DPI
Processing Cancelled

ব্যবহারকারীকে সহজ বাংলায় বা ইংরেজিতে সমস্যার কারণ ও সমাধানের নির্দেশনা দেখাতে হবে।

1️⃣9️⃣ Advanced Features (ঐচ্ছিক)

পরবর্তী পর্যায়ে যুক্ত করা যেতে পারে:

OCR Text Recognition
Business Card Scanner
Signature Cropper
QR Code Scanner
Barcode Scanner
ID Card Front/Back Scan
Watermark
Date Stamp
Custom Templates
Cloud Backup (ঐচ্ছিক)
AI Image Enhancement
Offline Processing
Preset Management
Photo Metadata Viewer
2️⃣0️⃣ AI Coding Instructions

AI Developer-এর জন্য নির্দেশনা:

প্রথমে সম্পূর্ণ Project Architecture তৈরি করো। তারপর প্রতিটি Module আলাদাভাবে বাস্তবায়ন করো।

কোড অবশ্যই Production-Ready, Maintainable এবং Modular হতে হবে।

CameraX ব্যবহার করে ক্যামেরা সিস্টেম তৈরি করো। Image Processing Engine-কে Camera UI থেকে আলাদা রাখো।

Crop, Resize, Compression, Rotation এবং Export-এর জন্য Reusable Components তৈরি করো।

Android-এর বিভিন্ন স্ক্রিন সাইজ ও API Level-এ Compatibility নিশ্চিত করো।

প্রতিটি Feature বাস্তবায়নের পর Testing ও Error Handling যুক্ত করো।

ছবির গুণমান, EXIF Orientation, Memory Usage এবং Export Accuracy-কে গুরুত্ব দাও।

প্রতিটি কোড ফাইলের নাম, অবস্থান, নির্ভরতা এবং সম্পূর্ণ কোড প্রদান করো। প্রয়োজন হলে ধাপে ধাপে বাস্তবায়ন করো।

অসম্পূর্ণ, Dummy অথবা শুধু UI প্রদর্শনকারী কোড প্রদান করবে না। বাস্তবে কাজ করে এমন Implementation তৈরি করবে।

⭐ আমার পরামর্শ: আপনার অ্যাপের বিশেষ সুবিধা

আপনার কাজের ধরন বিবেচনা করলে নিচের ৫টি ফিচারকে বিশেষ গুরুত্ব দিতে পারেন:

ফিচার	ব্যবহার
Custom Photo Size	সরকারি ফরমের ছবি
Target KB Compression	অনলাইন আবেদন
Batch Processing	একসঙ্গে অনেক ছবি
Passport Photo Sheet	প্রিন্টিং
Bengali / English UI	স্থানীয় ব্যবহারকারীদের জন্য

এগুলোকে কেন্দ্র করে অ্যাপ তৈরি করলে এটি সাধারণ Camera App-এর পাশাপাশি Photo Studio + Government Photo Preparation Tool হিসেবে কাজ করতে পারবে।