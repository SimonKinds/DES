all: 
	nvcc des.cu -o des -arch=sm_50 -g -O0
