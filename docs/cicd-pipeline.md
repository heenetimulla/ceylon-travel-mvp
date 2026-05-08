\# CI/CD Pipeline - Ceylon Travel



\## Purpose



This project uses GitHub Actions to automatically check and build the Flutter app when code is pushed to GitHub.



\## Current CI steps



1\. Checkout repository

2\. Set up Flutter

3\. Show Flutter version

4\. Install dependencies

5\. Analyze code

6\. Run tests

7\. Build Flutter web app

8\. Upload web build artifact



\## Why this is important



The CI pipeline proves that the app can build successfully in a clean environment, not only on the developer's laptop.



This is useful for DevOps because it shows automation, repeatability, and build validation.



\## Artifact



The pipeline saves the Flutter web build output as an artifact.



Artifact name:



ceylon-travel-web-build



Build folder:



build/web



\## Future improvements



\- Build Android APK

\- Add Firebase deployment

\- Add version tags

\- Add staging and production environments

\- Add rollback process

