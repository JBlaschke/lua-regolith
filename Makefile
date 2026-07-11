# SPDX-License-Identifier: AGPL-3.0-or-later
# lua-regolith -- full build.  libuv + luv are built via cmake. For a
# cmake-free build, use Makefile.lite.  All shared logic: mk/common.mk.

UV_BUILD := cmake
include mk/common.mk
