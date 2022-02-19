TERMUX_PKG_HOMEPAGE=https://www.haskell.org/ghc/
TERMUX_PKG_DESCRIPTION="The Glasgow Haskell Cross Compilation system for Android"
TERMUX_PKG_LICENSE="BSD 2-Clause, BSD 3-Clause, LGPL-2.1"
TERMUX_PKG_MAINTAINER="MrAdityaAlok <dev.aditya.alok@gmail.com>"
TERMUX_PKG_VERSION=8.10.7
TERMUX_PKG_SRCURL="http://downloads.haskell.org/~ghc/${TERMUX_PKG_VERSION}/ghc-${TERMUX_PKG_VERSION}-src.tar.xz"
TERMUX_PKG_SHA256=e3eef6229ce9908dfe1ea41436befb0455fefb1932559e860ad4c606b0d03c9d
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_BUILD_DEPENDS="iconv, libffi, libgmp, ncurses"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
--build=x86_64-unknown-linux
--host=x86_64-unknown-linux
--disable-ld-override
--with-system-libffi
--with-ffi-includes=${TERMUX_PREFIX}/include
--with-ffi-libraries=${TERMUX_PREFIX}/lib
--with-gmp-includes=${TERMUX_PREFIX}/include
--with-gmp-libraries=${TERMUX_PREFIX}/lib
--with-iconv-includes=${TERMUX_PREFIX}/include
--with-iconv-libraries=${TERMUX_PREFIX}/lib
--with-curses-libraries=${TERMUX_PREFIX}/lib
--with-curses-includes=${TERMUX_PREFIX}/include
--with-curses-libraries-stage0=/usr/lib
"

termux_step_pre_configure() {
	termux_setup_ghc

	[ "${TERMUX_ARCH}" = "arm" ] &&
		_TERMUX_HOST_PLATFORM="armv7a-linux-androideabi" || _TERMUX_HOST_PLATFORM="${TERMUX_HOST_PLATFORM}"

	TERMUX_PKG_EXTRA_CONFIGURE_ARGS+=" --target=${_TERMUX_HOST_PLATFORM}"

	_WRAPPER_BIN="${TERMUX_PKG_BUILDDIR}/_wrapper/bin"
	mkdir -p "${_WRAPPER_BIN}"

	for tool in llc opt; do
		local wrapper="${_WRAPPER_BIN}/${tool}"
		cat >"$wrapper" <<-EOF
			#!$(command -v sh)
			exec /usr/lib/llvm-12/bin/${tool} "\$@"
		EOF
		chmod 0700 "$wrapper"
	done

	local ar_wrapper="${_WRAPPER_BIN}/${_TERMUX_HOST_PLATFORM}-ar"
	cat >"$ar_wrapper" <<-EOF
		#!$(command -v sh)
		exec $(command -v ${AR}) "\$@"
	EOF
	chmod 0700 "$ar_wrapper"

	local strip_wrapper="${_WRAPPER_BIN}/${_TERMUX_HOST_PLATFORM}-strip"
	cat >"$strip_wrapper" <<-EOF
		#!$(command -v sh)
		exec $(command -v ${STRIP}) "\$@"
	EOF
	chmod 0700 "$strip_wrapper"

	export PATH="${_WRAPPER_BIN}:${PATH}"
	export LIBTOOL="$(command -v libtool)"

	local EXTRA_FLAGS="
	-optl-Wl,-rpath=${TERMUX_PREFIX}/lib
	-optl-Wl,--enable-new-dtags
	-optc-Os
	"
	[ "${TERMUX_ARCH}" != "i686" ] && EXTRA_FLAGS+=" -fllvm"

	# Suppress warnings for LLVM 13
	sed -i 's/LlvmMaxVersion=13/LlvmMaxVersion=14/' configure.ac

	cp mk/build.mk.sample mk/build.mk
	cat >>mk/build.mk <<-EOF
		SRC_HC_OPTS        = -O -H64m
		GhcStage2HcOpts    = ${EXTRA_FLAGS}
		GhcLibHcOpts       = ${EXTRA_FLAGS}
		SplitSections      = YES
		StripLibraries     = YES
		BuildFlavour       = quick-cross
		GhcLibWays         = v dyn
		STRIP_CMD          = ${STRIP}
		BUILD_PROF_LIBS    = NO
		HADDOCK_DOCS       = NO
		BUILD_SPHINX_HTML  = NO
		BUILD_SPHINX_PDF   = NO
		BUILD_MAN          = NO
		WITH_TERMINFO      = YES
		DYNAMIC_BY_DEFAULT = NO
		DYNAMIC_GHC_PROGRAMS = YES
		Stage1Only           = YES
	EOF

	patch -Np1 <<-EOF
		--- ghc-8.10.7/rules/build-package-data.mk      2021-06-21 12:24:36.000000000 +0530
		+++ ghc-8.10.7-patch/rules/build-package-data.mk 2022-01-27 20:31:28.901997265 +0530
		@@ -68,6 +68,12 @@
		 \$1_\$2_CONFIGURE_LDFLAGS = \$\$(SRC_LD_OPTS) \$\$(\$1_LD_OPTS) \$\$(\$1_\$2_LD_OPTS)
		 \$1_\$2_CONFIGURE_CPPFLAGS = \$\$(SRC_CPP_OPTS) \$\$(CONF_CPP_OPTS_STAGE\$3) \$\$(\$1_CPP_OPTS) \$\$(\$1_\$2_CPP_OPTS)

		+ifneq "\$3" "0"
		+ \$1_\$2_CONFIGURE_LDFLAGS += $LDFLAGS
		+ \$1_\$2_CONFIGURE_CPPFLAGS += $CPPFLAGS
		+ \$1_\$2_CONFIGURE_CFLAGS += $CFLAGS
		+endif
		+
		 \$1_\$2_CONFIGURE_OPTS += --configure-option=CFLAGS="\$\$(\$1_\$2_CONFIGURE_CFLAGS)"
		 \$1_\$2_CONFIGURE_OPTS += --configure-option=LDFLAGS="\$\$(\$1_\$2_CONFIGURE_LDFLAGS)"
		 \$1_\$2_CONFIGURE_OPTS += --configure-option=CPPFLAGS="\$\$(\$1_\$2_CONFIGURE_CPPFLAGS)"
	EOF

	./boot
}

termux_step_make() {
	make -j "${TERMUX_MAKE_PROCESSES}"
	make binary-dist BINARY_DIST_DIR="${TAR_OUTPUT_DIR}"

	tar_extract_tmpdir="$(mktemp -d)"
	tar -xf "${TAR_OUTPUT_DIR}"/*.tar.xz -C "${tar_extract_tmpdir}" --strip-components=1

	rm -f "${TAR_OUTPUT_DIR}"/*.tar.xz

	cp -f inplace/bin/ghc-cabal "${tar_extract_tmpdir}/utils/ghc-cabal/dist-install/build/tmp/ghc-cabal"
	cp -f inplace/bin/hpc "${tar_extract_tmpdir}/utils/hpc/dist-install/build/tmp/hpc"
	cp -f inplace/bin/runghc "${tar_extract_tmpdir}/utils/runghc/dist-install/build/tmp/runghc"

	tar -C "${tar_extract_tmpdir}" -cJf "${TAR_OUTPUT_DIR}/ghc-${TERMUX_PKG_VERSION}-${TERMUX_HOST_PLATFORM}.tar.xz" .
	exit 0
}
