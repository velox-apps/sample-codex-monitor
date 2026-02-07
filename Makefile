.PHONY: dev-frontend dev-backend dev build-frontend build clean

FRONTEND_DIR := ../original
DIST_TARGET  := frontend/dist

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

clean:
	swift package clean
	rm -rf $(DIST_TARGET)
