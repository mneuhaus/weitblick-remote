# Third-party notices

Weitblick Remote is licensed under the Apache License, Version 2.0 (see LICENSE). The app statically links the following third-party software. Everything else it uses (AppKit, SwiftUI, Core Audio, the CUPS printing library and other system frameworks) is part of macOS and is not distributed with the app.

## FreeRDP 3.32.1 (including WinPR)

https://www.freerdp.com, https://github.com/FreeRDP/FreeRDP

Copyright the FreeRDP contributors.

Licensed under the Apache License, Version 2.0. The full license text is in LICENSE. Built from the unmodified 3.32.1 release (client library, WinPR and the channels drdynvc, rdpgfx, disp, cliprdr, rdpsnd, audin, rdpdr, drive and printer).

FreeRDP contains the following code and data under other terms:

### MD4 implementation (winpr/libwinpr/crypto/md4.c)

    This software was written by Alexander Peslyak in 2001.  No copyright is
    claimed, and the software is hereby placed in the public domain.
    In case this attempt to disclaim copyright and place the software in the
    public domain is deemed null and void, then the software is
    Copyright (c) 2001 Alexander Peslyak and it is hereby released to the
    general public under the following terms:

    Redistribution and use in source and binary forms, with or without
    modification, are permitted.

    There's ABSOLUTELY NO WARRANTY, express or implied.

### Time zone mapping (winpr/libwinpr/timezone/WindowsZones.c)

Generated from the Unicode CLDR file windowsZones.xml.

    UNICODE LICENSE V3

    COPYRIGHT AND PERMISSION NOTICE

    Copyright © 1991-2026 Unicode, Inc.

    NOTICE TO USER: Carefully read the following legal agreement. BY
    DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
    SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
    TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
    DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of data files and any associated documentation (the "Data Files") or
    software and any associated documentation (the "Software") to deal in the
    Data Files or Software without restriction, including without limitation
    the rights to use, copy, modify, merge, publish, distribute, and/or sell
    copies of the Data Files or Software, and to permit persons to whom the
    Data Files or Software are furnished to do so, provided that either (a)
    this copyright and permission notice appear with all copies of the Data
    Files or Software, or (b) this copyright and permission notice appear in
    associated Documentation.

    THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
    KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
    THIRD PARTY RIGHTS.

    IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
    BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
    OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
    WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
    ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
    FILES OR SOFTWARE.

    Except as contained in this notice, the name of a copyright holder shall
    not be used in advertising or otherwise to promote the sale, use or other
    dealings in these Data Files or Software without prior written
    authorization of the copyright holder.

## OpenSSL 3.6.3 (libssl, libcrypto)

https://www.openssl.org

Copyright (c) 1998-2026 The OpenSSL Project Authors. Copyright (c) 1995-1998 Eric A. Young, Tim J. Hudson. All rights reserved.

Licensed under the Apache License, Version 2.0. The full license text is in LICENSE.
