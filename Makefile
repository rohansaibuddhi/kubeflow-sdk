# Copyright 2025 The Kubeflow Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Setting SHELL to bash allows bash commands to be executed by recipes.
# This is a requirement for 'setup-envtest.sh' in the test target.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

PROJECT_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
VENV_DIR := $(PROJECT_DIR)/.venv

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

#UV := $(shell which uv)

.PHONY: uv
uv: ## Install UV
	@command -v uv &> /dev/null || { \
	  curl -LsSf https://astral.sh/uv/install.sh | sh; \
	  echo "✅ uv has been installed."; \
	}

.PHONY: ruff
ruff: ## Install Ruff
	@uv run ruff --help &> /dev/null || uv tool install ruff

.PHONY: verify
verify: install-dev  ## install all required tools
	@uv lock --check
	@uv run ruff check --show-fixes --output-format=github .
	@uv run ruff format --check kubeflow

.PHONY: uv-venv
uv-venv:
	@if [ ! -d "$(VENV_DIR)" ]; then \
		echo "Creating uv virtual environment in $(VENV_DIR)..."; \
		uv venv; \
	else \
		echo "uv virtual environment already exists in $(VENV_DIR)."; \
	fi

.PHONY: release
release: install-dev
	@if [ -z "$(VERSION)" ]; then echo "Usage: make release VERSION=0.1.0"; exit 1; fi
	@V_NO_V=$(VERSION); \
	sed -i.bak "s/^__version__ = \".*\"/__version__ = \"$$V_NO_V\"/" kubeflow/__init__.py && \
	rm -f kubeflow/__init__.py.bak
	@PREV_TAG=$$(git tag -l --sort=-creatordate | head -1); \
	CHANGELOG_FILE=CHANGELOG/CHANGELOG-$$(echo $(VERSION) | cut -d. -f1-2).md; \
	if [ -z "$$PREV_TAG" ]; then \
	  GITHUB_TOKEN=$${GITHUB_TOKEN} git-cliff --tag $(VERSION) -o $$CHANGELOG_FILE; \
	elif [ -f "$$CHANGELOG_FILE" ]; then \
	  GITHUB_TOKEN=$${GITHUB_TOKEN} git-cliff $$PREV_TAG..HEAD --tag $(VERSION) --prepend $$CHANGELOG_FILE; \
	else \
	  GITHUB_TOKEN=$${GITHUB_TOKEN} git-cliff $$PREV_TAG..HEAD --tag $(VERSION) -o $$CHANGELOG_FILE; \
	fi

 # make test-python will produce html coverage by default. Run with `make test-python report=xml` to produce xml report.
.PHONY: test-python
test-python: uv-venv
	@uv sync
	@uv run coverage run --source=kubeflow.trainer.backends.kubernetes.backend,kubeflow.trainer.utils.utils -m pytest ./kubeflow/trainer/backends/kubernetes/backend_test.py ./kubeflow/trainer/utils/utils_test.py
	@uv run coverage report -m kubeflow/trainer/backends/kubernetes/backend.py kubeflow/trainer/utils/utils.py
ifeq ($(report),xml)
	@uv run coverage xml
else
	@uv run coverage html
endif


.PHONY: install-dev
install-dev: uv uv-venv ruff ## Install uv, create .venv, sync deps; DEV=1 to include dev group; EXTRAS=comma,list for extras
	@echo "Using virtual environment at: $(VENV_DIR)"
	@echo "Syncing dependencies with uv..."
	@uv sync
	@echo "Environment is ready."
