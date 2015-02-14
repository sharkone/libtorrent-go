###############################################################################
# Common
###############################################################################
NAME = libtorrent-go

###############################################################################
# Development environment
###############################################################################
PLATFORMS = android-arm		\
			darwin-x64 		\
			linux-x86 		\
			linux-x64 		\
			linux-arm 		\
			windows-x86 	\
			windows-x64

DOCKER 		 = docker
DOCKER_IMAGE = steeve/$(NAME)
DOCKER_FILES = $(addsuffix /Dockerfile, $(PLATFORMS))

dev-build: $(DOCKER_FILES)
	for i in $(PLATFORMS); do 																													\
		$(DOCKER) build -t $(DOCKER_IMAGE):$$i $$i || exit 1;																					\
		$(DOCKER) run -ti --rm -v $(HOME):$(HOME) -e GOPATH=$(shell go env GOPATH) -w $(shell pwd) $(DOCKER_IMAGE):$$i make cc-build || exit 1;	\
	done

dev-clean:
	for i in $(PLATFORMS); do 							\
		$(DOCKER) rmi $(DOCKER_IMAGE):$$i || exit 1;	\
	done

###############################################################################
# Cross-compilation environment (inside each Docker image)
###############################################################################
GO_PACKAGE = github.com/steeve/$(NAME)

CC 		   = cc
CXX		   = c++
PKG_CONFIG = pkg-config

ifneq ($(CROSS_TRIPLE),)
	CC 	:= $(CROSS_TRIPLE)-$(CC)
	CXX := $(CROSS_TRIPLE)-$(CXX)
endif

include platform_target.mk

ifeq ($(TARGET_ARCH),x86)
	GOARCH = 386
else ifeq ($(TARGET_ARCH),x64)
	GOARCH = amd64
else ifeq ($(TARGET_ARCH),arm)
	GOARCH = arm
	GOARM  = 6
endif

ifeq ($(TARGET_OS), windows)
	GOOS = windows
else ifeq ($(TARGET_OS), darwin)
	GOOS = darwin
else ifeq ($(TARGET_OS), linux)
	GOOS = linux
else ifeq ($(TARGET_OS), android)
	GOOS  =	android
	GOARM =	7
endif

ifneq ($(CROSS_ROOT),)
	CROSS_CFLAGS 	= -I$(CROSS_ROOT)/include -I$(CROSS_ROOT)/$(CROSS_TRIPLE)/include
	CROSS_LDFLAGS	= -L$(CROSS_ROOT)/lib
	PKG_CONFIG_PATH = $(CROSS_ROOT)/lib/pkgconfig
endif

LIBTORRENT_CFLAGS  = $(shell PKG_CONFIG_PATH=$(PKG_CONFIG_PATH) $(PKG_CONFIG) --cflags libtorrent-rasterbar)
LIBTORRENT_LDFLAGS = $(shell PKG_CONFIG_PATH=$(PKG_CONFIG_PATH) $(PKG_CONFIG) --static --libs libtorrent-rasterbar)
DEFINE_IGNORES 	   = __STDC__|_cdecl|__cdecl|_fastcall|__fastcall|_stdcall|__stdcall|__declspec
CC_DEFINES 		   = $(shell echo | $(CC) -dM -E - | grep -v -E "$(DEFINE_IGNORES)" | sed -E "s/\#define[[:space:]]+([a-zA-Z0-9_()]+)[[:space:]]+(.*)/-D\1="\2"/g" | tr '\n' ' ')

ifeq ($(TARGET_OS), windows)
	CC_DEFINES += -DSWIGWIN
	CC_DEFINES += -D_WIN32_WINNT=0x0501
	ifeq ($(TARGET_ARCH), x64)
		CC_DEFINES += -DSWIGWORDSIZE32
	endif
else ifeq ($(TARGET_OS), darwin)
	CC_DEFINES += -DSWIGMAC
	CC_DEFINES += -DBOOST_HAS_PTHREADS
endif

OUT_PATH    = $(shell go env GOPATH)/pkg/$(GOOS)_$(GOARCH)
OUT_LIBRARY = $(OUT_PATH)/$(GO_PACKAGE).a
ifeq ($(TARGET_OS), windows)
	OUT_LIBRARY_SHARED = $(OUT_PATH)/$(GO_PACKAGE).dll
	SONAME 			   = $(shell basename $(OUT_LIBRARY_SHARED))
endif

ifeq ($(TARGET_OS), windows)
cc-build: $(OUT_LIBRARY_SHARED)
else
cc-build: $(OUT_LIBRARY)
endif

$(OUT_LIBRARY):
	SWIG_FLAGS='$(CC_DEFINES) $(LIBTORRENT_CFLAGS)'	\
	SONAME=$(SONAME)								\
	CC=$(CC) CXX=$(CXX)								\
	PKG_CONFIG_PATH=$(PKG_CONFIG_PATH)				\
	CGO_ENABLED=1									\
	GOOS=$(GOOS) GOARCH=$(GOARCH) GOARM=$(GOARM)	\
	PATH=.:$$PATH  									\
	go install -v -x

$(OUT_LIBRARY_SHARED): cc-clean $(OUT_LIBRARY)
	cp $(OUT_LIBRARY) $(OUT_LIBRARY).raw
	cd `mktemp -d` &&																								\
		pwd && 																										\
		ar x $(OUT_LIBRARY).raw && 																					\
		go tool pack r $(OUT_LIBRARY) `ar t $(OUT_LIBRARY).raw | grep -v _wrap` && 									\
		$(CXX) -shared -static-libgcc -static-libstdc++ -o $(OUT_LIBRARY_SHARED) *_wrap $(LIBTORRENT_LDFLAGS) &&	\
		rm -rf `pwd`
	rm -rf $(OUT_LIBRARY).raw

cc-clean:
	rm -rf $(OUT_LIBRARY) $(OUT_LIBRARY_SHARED)
