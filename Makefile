.PHONY: dev-frontend dev-backend dev build-frontend build bundle run clean

FRONTEND_DIR := ../CodexMonitor
DIST_TARGET  := frontend/dist
VELOX        := ../velox/.build/release/velox

dev-frontend:
	cd $(FRONTEND_DIR) && npm run dev

dev-backend:
	VELOX_DEV_URL=http://localhost:1420 swift run CodexMonitor

dev:
	$(MAKE) dev-frontend &
	sleep 3
	$(MAKE) dev-backend

build-frontend:
	cd $(FRONTEND_DIR) && npm run build
	rm -rf $(DIST_TARGET)
	mkdir -p frontend
	cp -r $(FRONTEND_DIR)/dist $(DIST_TARGET)

build: build-frontend
	swift build -c release

$(VELOX):
	cd ../velox && swift build -c release --product velox

bundle: build-frontend $(VELOX)
	$(VELOX) build --bundle

run: bundle
	xattr -cr .build/release/CodexMonitor.app
	open .build/release/CodexMonitor.app

clean:
	swift package clean
	rm -rf $(DIST_TARGET)
