#!/bin/sh -e
## Taken crom the crouton target, with removed crouton dependencies.
## Just compiles and installs dummy_drv.so.

# Copyright (c) 2016 The crouton Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Download the latest xf86-video-dummy package
urlbase="http://xorg.freedesktop.org/releases/individual/driver/"

DUMMYBUILDTMP="`mktemp -d dummy-driver.XXXXXX --tmpdir=/tmp`"

#addtrap "rm -rf --one-file-system '$DUMMYBUILDTMP'"

# Convert an automake Makefile.am into a shell script, and provide useful
# functions to compile libraries and executables.
# Needs to be run in the same directory as the Makefile.am file.
# This outputs the converted Makefile.am to stdout, which is meant to be
# piped to sh -s (see audio and xiat for examples)
convert_automake() {
    echo '
        top_srcdir=".."
        top_builddir=".."
    '
    sed -e '
        # Concatenate lines ending in \
        : start; /\\$/{N; b start}
        s/ *\\\n[ \t]*/ /g
        # Convert automake to shell
        s/^[^ ]*:/#\0/
        s/^\t/#\0/
        s/\t/ /g
        s/ *= */=/
        s/\([^ ]*\) *+= */\1=${\1}\ /
        s/ /\\ /g
        y/()/{}/
        s/if\\ \(.*\)/if [ -n "${\1}" ]; then/
        s/endif/fi/
    ' 'Makefile.am'
    echo '
        # buildsources: Build all source files for target
        #  $1: target
        #  $2: additional gcc flags
        # Prints a list of .o files
        buildsources() {
            local target="$1"
            local extragccflags="$2"

            eval local sources=\"\$${target}_SOURCES\"
            eval local cppflags=\"\$${target}_CPPFLAGS\"
            local cflags="$cppflags ${CFLAGS} ${AM_CFLAGS}"

            for dep in $sources; do
                if [ "${dep%.c}" != "$dep" ]; then
                    ofile="${dep%.c}.o"
                    gcc -c "$dep" -o "$ofile" '"$archgccflags"' \
                        $cflags $extragccflags 1>&2 || return $?
                    echo -n "$ofile "
                fi
            done
        }

        # fixlibadd:
        # Fix list of libraries ($1): replace lib<x>.la by -l<x>
        fixlibadd() {
            for libdep in $*; do
                if [ "${libdep%.la}" != "$libdep" ]; then
                    libdep="${libdep%.la}"
                    libdep="-l${libdep#lib}"
                fi
                echo -n "$libdep "
            done
        }

        # buildlib: Build a library
        #  $1: library name
        #  $2: additional linker flags
        buildlib() {
            local lib="$1"
            local extraflags="$2"
            local ofiles
            # local eats the return status: separate the 2 statements
            ofiles="`buildsources "${lib}_la" "-fPIC -DPIC"`"

            eval local libadd=\"\$${lib}_la_LIBADD\"
            eval local ldflags=\"\$${lib}_la_LDFLAGS\"

            libadd="`fixlibadd $libadd`"

            # Detect library version (e.g. 0.0.0)
            local fullver="`echo -n "$ldflags" | \
                      sed -n '\''y/:/./; \
                                 s/.*-version-info \([0-9.]*\)$/\\1/p'\''`"
            local shortver=""
            # Get "short" library version (e.g. 0)
            if [ -n "$fullver" ]; then
                shortver=".${fullver%%.*}"
                fullver=".$fullver"
            fi
            local fullso="$lib.so$fullver"
            local shortso="$lib.so$shortver"
            gcc -shared -fPIC -DPIC $ofiles $libadd -o "$fullso" \
                '"$archgccflags"' $extraflags -Wl,-soname,"$shortso"
            if [ -n "$fullver" ]; then
                ln -sf "$fullso" "$shortso"
                # Needed at link-time only
                ln -sf "$shortso" "$lib.so"
            fi
        }

        # buildexe: Build an executable file
        #  $1: executable file name
        #  $2: additional linker flags
        buildexe() {
            local exe="$1"
            local extraflags="$2"
            local ofiles="`buildsources "$exe" ""`"

            eval local ldadd=\"\$${exe}_LDADD\"
            eval local ldflags=\"\$${exe}_LDFLAGS\"

            ldadd="`fixlibadd $ldadd`"

            gcc $ofiles $ldadd -o "$exe" '"$archgccflags"' $extraflags
        }
    '
}

echo "Download Xorg dummy driver..." 1>&2

wget -O "$DUMMYBUILDTMP/dummy.tar.gz" "$urlbase/xf86-video-dummy-0.3.7.tar.gz"

(
    cd "$DUMMYBUILDTMP"
    # -m prevents "time stamp is in the future" spam
    tar --strip-components=1 -xmf dummy.tar.gz

    echo "Patching Xorg dummy driver (xrandr 1.2 support)..." 1>&2
    patch -p1 <<EOF
diff --git a/src/dummy_driver.c b/src/dummy_driver.c
index 6062c39..3414a6d 100644
--- a/src/dummy_driver.c
+++ b/src/dummy_driver.c
@@ -34,6 +34,8 @@
 #include <X11/extensions/Xv.h>
 #endif
 
+#include "xf86Crtc.h"
+
 /*
  * Driver data structures.
  */
@@ -178,6 +180,115 @@ dummySetup(pointer module, pointer opts, int *errmaj, int *errmin)
 #endif /* XFree86LOADER */
 
 static Bool
+size_valid(ScrnInfoPtr pScrn, int width, int height)
+{
+    /* Guard against invalid parameters */
+    if (width == 0 || height == 0 ||
+        width > DUMMY_MAX_WIDTH || height > DUMMY_MAX_HEIGHT)
+        return FALSE;
+
+    /* videoRam is in kb, divide first to avoid 32-bit int overflow */
+    if ((width*height+1023)/1024*pScrn->bitsPerPixel/8 > pScrn->videoRam)
+        return FALSE;
+
+    return TRUE;
+}
+
+static Bool
+dummy_xf86crtc_resize(ScrnInfoPtr pScrn, int width, int height)
+{
+    int old_width, old_height;
+
+    old_width = pScrn->virtualX;
+    old_height = pScrn->virtualY;
+
+    if (size_valid(pScrn, width, height)) {
+        PixmapPtr rootPixmap;
+        ScreenPtr pScreen = pScrn->pScreen;
+
+        pScrn->virtualX = width;
+        pScrn->virtualY = height;
+
+        rootPixmap = pScreen->GetScreenPixmap(pScreen);
+        if (!pScreen->ModifyPixmapHeader(rootPixmap, width, height,
+                                         -1, -1, -1, NULL)) {
+            pScrn->virtualX = old_width;
+            pScrn->virtualY = old_height;
+            return FALSE;
+        }
+
+        pScrn->displayWidth = rootPixmap->devKind /
+            (rootPixmap->drawable.bitsPerPixel / 8);
+
+        return TRUE;
+    } else {
+        return FALSE;
+    }
+}
+
+static const xf86CrtcConfigFuncsRec dummy_xf86crtc_config_funcs = {
+    dummy_xf86crtc_resize
+};
+
+static xf86OutputStatus
+dummy_output_detect(xf86OutputPtr output)
+{
+    return XF86OutputStatusConnected;
+}
+
+static int
+dummy_output_mode_valid(xf86OutputPtr output, DisplayModePtr pMode)
+{
+    if (size_valid(output->scrn, pMode->HDisplay, pMode->VDisplay)) {
+        return MODE_OK;
+    } else {
+        return MODE_MEM;
+    }
+}
+
+static DisplayModePtr
+dummy_output_get_modes(xf86OutputPtr output)
+{
+    return NULL;
+}
+
+static void
+dummy_output_dpms(xf86OutputPtr output, int dpms)
+{
+    return;
+}
+
+static const xf86OutputFuncsRec dummy_output_funcs = {
+    .detect = dummy_output_detect,
+    .mode_valid = dummy_output_mode_valid,
+    .get_modes = dummy_output_get_modes,
+    .dpms = dummy_output_dpms,
+};
+
+static Bool
+dummy_crtc_set_mode_major(xf86CrtcPtr crtc, DisplayModePtr mode,
+			  Rotation rotation, int x, int y)
+{
+    crtc->mode = *mode;
+    crtc->x = x;
+    crtc->y = y;
+    crtc->rotation = rotation;
+
+    return TRUE;
+}
+
+static void
+dummy_crtc_dpms(xf86CrtcPtr output, int dpms)
+{
+    return;
+}
+
+static const xf86CrtcFuncsRec dummy_crtc_funcs = {
+    .set_mode_major = dummy_crtc_set_mode_major,
+    .dpms = dummy_crtc_dpms,
+};
+
+static Bool
 DUMMYGetRec(ScrnInfoPtr pScrn)
 {
     /*
@@ -283,6 +394,8 @@ DUMMYPreInit(ScrnInfoPtr pScrn, int flags)
     DUMMYPtr dPtr;
     int maxClock = 230000;
     GDevPtr device = xf86GetEntityInfo(pScrn->entityList[0])->device;
+    xf86OutputPtr output;
+    xf86CrtcPtr crtc;
 
     if (flags & PROBE_DETECT) 
 	return TRUE;
@@ -346,13 +459,6 @@ DUMMYPreInit(ScrnInfoPtr pScrn, int flags)
     if (!xf86SetDefaultVisual(pScrn, -1)) 
 	return FALSE;
 
-    if (pScrn->depth > 1) {
-	Gamma zeros = {0.0, 0.0, 0.0};
-
-	if (!xf86SetGamma(pScrn, zeros))
-	    return FALSE;
-    }
-
     xf86CollectOptions(pScrn, device->options);
     /* Process the options */
     if (!(dPtr->Options = malloc(sizeof(DUMMYOptions))))
@@ -382,64 +488,45 @@ DUMMYPreInit(ScrnInfoPtr pScrn, int flags)
 		   maxClock);
     }
 
-    pScrn->progClock = TRUE;
-    /*
-     * Setup the ClockRanges, which describe what clock ranges are available,
-     * and what sort of modes they can be used for.
-     */
-    clockRanges = (ClockRangePtr)xnfcalloc(sizeof(ClockRange), 1);
-    clockRanges->next = NULL;
-    clockRanges->ClockMulFactor = 1;
-    clockRanges->minClock = 11000;   /* guessed §§§ */
-    clockRanges->maxClock = 300000;
-    clockRanges->clockIndex = -1;		/* programmable */
-    clockRanges->interlaceAllowed = TRUE; 
-    clockRanges->doubleScanAllowed = TRUE;
-
-    /* Subtract memory for HW cursor */
-
-
-    {
-	int apertureSize = (pScrn->videoRam * 1024);
-	i = xf86ValidateModes(pScrn, pScrn->monitor->Modes,
-			      pScrn->display->modes, clockRanges,
-			      NULL, 256, DUMMY_MAX_WIDTH,
-			      (8 * pScrn->bitsPerPixel),
-			      128, DUMMY_MAX_HEIGHT, pScrn->display->virtualX,
-			      pScrn->display->virtualY, apertureSize,
-			      LOOKUP_BEST_REFRESH);
-
-       if (i == -1)
-           RETURN;
-    }
+    xf86CrtcConfigInit(pScrn, &dummy_xf86crtc_config_funcs);
+
+    xf86CrtcSetSizeRange(pScrn, 256, 256, DUMMY_MAX_WIDTH, DUMMY_MAX_HEIGHT);
+
+    crtc = xf86CrtcCreate(pScrn, &dummy_crtc_funcs);
+
+    output = xf86OutputCreate (pScrn, &dummy_output_funcs, "default");
+
+    output->possible_crtcs = 0x7f;
 
-    /* Prune the modes marked as invalid */
-    xf86PruneDriverModes(pScrn);
+    xf86InitialConfiguration(pScrn, TRUE);
+
+    if (pScrn->depth > 1) {
+	Gamma zeros = {0.0, 0.0, 0.0};
+
+	if (!xf86SetGamma(pScrn, zeros))
+	    return FALSE;
+    }
 
-    if (i == 0 || pScrn->modes == NULL) {
+    if (pScrn->modes == NULL) {
 	xf86DrvMsg(pScrn->scrnIndex, X_ERROR, "No valid modes found\n");
 	RETURN;
     }
 
-    /*
-     * Set the CRTC parameters for all of the modes based on the type
-     * of mode, and the chipset's interlace requirements.
-     *
-     * Calling this is required if the mode->Crtc* values are used by the
-     * driver and if the driver doesn't provide code to set them.  They
-     * are not pre-initialised at all.
-     */
-    xf86SetCrtcForModes(pScrn, 0); 
- 
     /* Set the current mode to the first in the list */
     pScrn->currentMode = pScrn->modes;
 
-    /* Print the list of modes being used */
-    xf86PrintModes(pScrn);
+    /* Set default mode in CRTC */
+    crtc->funcs->set_mode_major(crtc, pScrn->currentMode, RR_Rotate_0, 0, 0);
 
     /* If monitor resolution is set on the command line, use it */
     xf86SetDpi(pScrn, 0, 0);
 
+    /* Set monitor size based on DPI */
+    output->mm_width = pScrn->xDpi > 0 ?
+        (pScrn->virtualX * 254 / (10*pScrn->xDpi)) : 0;
+    output->mm_height = pScrn->yDpi > 0 ?
+        (pScrn->virtualY * 254 / (10*pScrn->yDpi)) : 0;
+
     if (xf86LoadSubModule(pScrn, "fb") == NULL) {
 	RETURN;
     }
@@ -559,6 +646,8 @@ DUMMYScreenInit(SCREEN_INIT_ARGS_DECL)
 
     if (!miSetPixmapDepths ()) return FALSE;
 
+    pScrn->displayWidth = pScrn->virtualX;
+
     /*
      * Call the framebuffer layer's ScreenInit function, and fill in other
      * pScreen fields.
@@ -597,23 +686,6 @@ DUMMYScreenInit(SCREEN_INIT_ARGS_DECL)
     if (dPtr->swCursor)
 	xf86DrvMsg(pScrn->scrnIndex, X_CONFIG, "Using Software Cursor.\n");
 
-    {
-
-	 
-	BoxRec AvailFBArea;
-	int lines = pScrn->videoRam * 1024 /
-	    (pScrn->displayWidth * (pScrn->bitsPerPixel >> 3));
-	AvailFBArea.x1 = 0;
-	AvailFBArea.y1 = 0;
-	AvailFBArea.x2 = pScrn->displayWidth;
-	AvailFBArea.y2 = lines;
-	xf86InitFBManager(pScreen, &AvailFBArea); 
-	
-	xf86DrvMsg(pScrn->scrnIndex, X_INFO, 
-		   "Using %i scanlines of offscreen memory \n"
-		   , lines - pScrn->virtualY);
-    }
-
     xf86SetBackingStore(pScreen);
     xf86SetSilkenMouse(pScreen);
 	
@@ -640,6 +712,9 @@ DUMMYScreenInit(SCREEN_INIT_ARGS_DECL)
 			     | CMAP_RELOAD_ON_MODE_SWITCH))
 	return FALSE;
 
+    if (!xf86CrtcScreenInit(pScreen))
+        return FALSE;
+
 /*     DUMMYInitVideo(pScreen); */
 
     pScreen->SaveScreen = DUMMYSaveScreen;
EOF

    # Fake version 0.3.8
    package="xf86-video-dummy"
    major='0'
    minor='3'
    patch='8'
    version="$major.$minor.$patch"

    sed -e '
        s/#undef \(HAVE_.*\)$/#define \1 1/
        s/#undef \(USE_.*\)$/#define \1 1/
        s/#undef \(STDC_HEADERS\)$/#define \1 1/
        s/#undef \(.*VERSION\)$/#define \1 "'$version'"/
        s/#undef \(.*VERSION_MAJOR\)$/#define \1 '$major'/
        s/#undef \(.*VERSION_MINOR\)$/#define \1 '$minor'/
        s/#undef \(.*VERSION_PATCHLEVEL\)$/#define \1 '$patch'/
        s/#undef \(.*PACKAGE_STRING\)$/#define \1 "'"$package $version"'"/
        s/#undef \(.*PACKAGE_*\)$/#define \1 "'$package'"/
    ' config.h.in > config.h

    echo "Compiling Xorg dummy driver..." 1>&2

    cd src
    # Convert Makefile.am to a shell script, and run it.
    {
        echo '
            DGA=1
            CFLAGS="-std=gnu99 -O2 -g -DHAVE_CONFIG_H -I.. -I."
            XORG_CFLAGS="'"`pkg-config --cflags xorg-server`"'"
        '

        convert_automake

        echo '
            buildlib dummy_drv
        '
    } | sh -s -e $SETOPTIONS

    echo "Installing Xorg dummy driver..." 1>&2

    set -x
    DRIVERDIR="/usr/lib/xorg/modules/drivers"
    mkdir -p "$DRIVERDIR/"
    #/usr/bin/install -s dummy_drv.so "$DRIVERDIR/"
) # End compilation subshell
