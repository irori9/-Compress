Third-Party Notices

This project plans to integrate the following third-party libraries for archive extraction. At the current stage, adapters are implemented with simulated pipelines and injectable inspectors to validate flows without linking the actual libraries. When integrating the real libraries, please review and comply with each license below.

1) UnrarKit (RAR extraction)
   - Repository: https://github.com/abbeycode/UnrarKit
   - License: UnRAR License (from RARLab)
   - Important terms (summary, not a substitute for the license):
     - The UnRAR source may be used in software to extract RAR archives.
     - It may not be used to create a RAR-compatible archiver.
     - The UnRAR source may not be used to reverse-engineer the RAR compression algorithm.
   - Action items:
     - When integrating UnrarKit, include its license in your app bundle and about box.
     - Ensure your usage is limited to extraction and complies with UnRAR terms.

2) LzmaSDK-ObjC (7z extraction)
   - Repository: https://github.com/OlehKulykov/LzmaSDK-ObjC
   - License: Based on 7-Zip LZMA SDK license (public domain / permissive). Review the repository for exact terms.
   - Action items:
     - Include appropriate notices if required by the upstream project.
     - Verify compatibility with your distribution and internal policies.

Bridging Header
- The project contains a placeholder bridging header at:
  Bridging/ArchiveManager-Bridging-Header.h
- When integrating UnrarKit and LzmaSDK-ObjC, add the necessary Objective-C imports, for example:
  #import <UnrarKit/UnrarKit.h>
  #import <LzmaSDK_ObjC/LzmaSDKObjCReader.h>

Attribution in Documentation
- Update README and in-app acknowledgements to reflect the above libraries and licenses once integrated.
