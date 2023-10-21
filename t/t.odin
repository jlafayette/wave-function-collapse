package main

import "core:c"
import "core:fmt"
import "vendor:stb/image"
import "core:math"
import "core:math/rand"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

rand_experiement :: proc() {
	t := time.now()

	r : rand.Rand
	rand.init(&r, u64(t._nsec))

	counts : [6]int

	total := 1000000
	for i:=0; i<total; i+=1 {
		f := rand.float32(&r)
		// fmt.println("f:", f)
		f *= f32(6)
		// fmt.println("f:", f)
		idx :int= cast(int)math.floor(f)
		// fmt.println("idx:", idx)
		counts[idx] += 1
	}
	min := total
	max := 0
	for x in counts {
		min = math.min(min, x)
		max = math.max(max, x)
	}
	fmt.println("diff:", max - min)
	fmt.println("min:", min, "max:", max, "\ncounts:", counts)
}


create_square :: proc() {
	w :: 10
	h :: 10
	ch :: 1
	stride :: w * ch
	size :: w * h * ch
	buf: [size]byte
	for y:=0; y<h; y+=1 {
		for x:=0; x<w; x+=1 {
			i := y*w + x
			if x == 0 || x == w-1 || y == 0 || y == h-1 {
				buf[i] = 200
			} else {
				buf[i] = 20
			}
		}
	}
	err := image.write_png("square.png", 10, 10, 1, raw_data(buf[:]), stride)
	fmt.println("err:", err)
}

combine_inputs :: proc() {
	args := os.args[1:]
	fmt.println(args)
	assert(len(args) >= 2)

	src_images := make([][^]byte, len(args))
	w, h, ch, stride : i32

	for arg, i in args {
		src_path := strings.clone_to_cstring(arg)
		src_images[i] = image.load(src_path, &w, &h, &ch, 0)
		assert(src_images[i] != nil)
		stride = w * ch
		fmt.println("image:", i, w, h, ch, stride)
	}

	ow, oh, och : i32
	ow = w * i32(len(args))
	oh = h
	och = 3
	ostride : i32 = ow * ch
	osize := ow * oh * ch
	oimg := make([]byte, osize)
	slice.fill(oimg, 255)
	for _, i in oimg {
		switch i % 3 {
		case 0:
			oimg[i] = 255
		case 1:
			oimg[i] = 0
		case 2:
			oimg[i] = 0
		case:
		}
	}

	for src_img, img_i in src_images {
		x_offset: i32 = cast(i32)img_i * w
		fmt.printf("image %d x_offset=%d\n", img_i, x_offset)
		for y: i32 = 0; y < h; y += 1 {
			for x: i32 = 0; x < w; x += 1 {
				i := (y*stride) + (x*ch)
				r := src_img[i]
				g := src_img[i+1]
				b := src_img[i+2]
				oi := (y*ostride) + ((x+x_offset)*och)
				oimg[oi] = r
				oimg[oi+1] = g
				oimg[oi+2] = b
				// fmt.print("i:", i, "oi", oi)
				// fmt.print(x, y, i, " ")
			}
		}
		// fmt.print("\n")
	}

	out_filename : cstring = "out.png"
	image.write_png(out_filename, ow, oh, och, &oimg[0], ostride)
}

main :: proc() {
	combine_inputs()
}

