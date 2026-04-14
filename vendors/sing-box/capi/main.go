// C API wrapper for sing-box sidecar mode.
// Build: go build -buildmode=c-archive -tags with_utls -o libsingbox.a ./cmd/capi
//
// Exposes sing-box as an in-process library for iOS (where process spawning
// is not allowed). The API mirrors SingBoxProcess.java from ics-openvpn.

package main

import "C"

import (
	"context"
	"sync"
	"unsafe"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json"
)

var (
	mu       sync.Mutex
	instance *box.Box
	cancel   context.CancelFunc
)

// sing_box_start starts sing-box with the given JSON configuration.
// Returns 0 on success, negative on error.
//
//export sing_box_start
func sing_box_start(configJSON *C.char) C.int {
	mu.Lock()
	defer mu.Unlock()

	if instance != nil {
		return -1
	}

	goConfig := C.GoString(configJSON)
	ctx := context.Background()
	ctx = box.Context(ctx,
		include.InboundRegistry(),
		include.OutboundRegistry(),
		include.EndpointRegistry(),
		include.DNSTransportRegistry(),
		include.ServiceRegistry(),
	)

	options, err := json.UnmarshalExtendedContext[option.Options](ctx, []byte(goConfig))
	if err != nil {
		return -2
	}

	ctx, cancelFn := context.WithCancel(ctx)

	b, err := box.New(box.Options{
		Context: ctx,
		Options: options,
	})
	if err != nil {
		cancelFn()
		return -3
	}

	if err = b.Start(); err != nil {
		b.Close()
		cancelFn()
		return -4
	}

	instance = b
	cancel = cancelFn
	return 0
}

// sing_box_stop stops the running sing-box instance.
//
//export sing_box_stop
func sing_box_stop() {
	mu.Lock()
	defer mu.Unlock()

	if instance != nil {
		instance.Close()
		instance = nil
	}
	if cancel != nil {
		cancel()
		cancel = nil
	}
}

// sing_box_is_running returns 1 if running, 0 otherwise.
//
//export sing_box_is_running
func sing_box_is_running() C.int {
	mu.Lock()
	defer mu.Unlock()
	if instance != nil {
		return 1
	}
	return 0
}

// sing_box_version returns the version string.
//
//export sing_box_version
func sing_box_version() *C.char {
	return C.CString(constant.Version)
}

var _ = unsafe.Pointer(nil)

func main() {}
