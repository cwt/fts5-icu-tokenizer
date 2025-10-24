#!/bin/bash

cppcheck --check-level=exhaustive --enable=warning,style,performance,portability --std=c11 --verbose src

