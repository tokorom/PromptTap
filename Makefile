SHELL := /bin/zsh

bump_type=patch
deploy_branch=deploy

changelog := "./Changelog.txt"
xcconfig := "./Version.xcconfig"
increment_version_script := "./scripts/increment_version.zsh"
build_number_key := "APP_BUILD_NUMBER"
marketing_version_key := "APP_VERSION"

github_release_script := "./scripts/github_release.zsh"
github_repo := "tokorom/PromptFlow"
github_token := "${GITHUB_TOKEN}"

build_number = $$(zsh -c "source $(increment_version_script) && get_build_number $(xcconfig) $(build_number_key)")
marketing_version = $$(zsh -c "source $(increment_version_script) && get_marketing_version $(xcconfig) $(marketing_version_key)")

deploy_to_xcode_cloud:
	${EDITOR} $(changelog)
	git add $(changelog)
	git commit -m "Update changelog" || true
	zsh -c "source $(increment_version_script) && increment_marketing_version $(xcconfig) $(marketing_version_key) $(bump_type)"
	zsh -c "source $(increment_version_script) && increment_build_number $(xcconfig) $(build_number_key)"
	git add $(xcconfig)
	git commit -m "Bump up app version to $(marketing_version) ($(build_number))" || true
	git push origin @
	zsh -c "source $(github_release_script) && github_release $(github_repo) $(marketing_version) $(github_token) $(changelog)"
	git ls-remote --exit-code . origin/$(deploy_branch) && git push origin --delete $(deploy_branch) || true
	git push origin HEAD:$(deploy_branch)
help:
	@echo "[Usage]"
	@echo "  make deploy_to_xcode_cloud"
	@echo "  make deploy_to_xcode_cloud bump_type=minor"
	@echo "  make deploy_to_xcode_cloud bump_type=major"
lint:
	swift format lint --recursive app
format:
	swift format format --recursive --in-place app
