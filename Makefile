SOURCE_CODE = source/now/*.d source/now/commands/*.d source/now/system_command/* source/now/nodes/*.d source/now/nodes/*/*.d source/now/nodes/*/*/*.d

dist/now: ${SOURCE_CODE}
	gdc \
		-static-libphobos -static-libgcc \
		cli/source/now/now.d \
		$^ \
		-Isource -Icli/source \
		-O2 -o dist/now

release: dist/now
	strip $^

dist/now.debug: ${SOURCE_CODE}
	gdc -fdebug \
		-static-libphobos -static-libgcc \
		cli/source/now/now.d \
		$^ \
		-Isource -Icli/source \
		-O1 -o dist/now.debug


clean:
	-rm -f dist/libnow.* dist/now*
	-rm -f build/*
