"""
SSTV示例代码
"""

using SSTV
using Images

# 加载图像
img_path = joinpath(@__DIR__, "Julia.png")
img = load(img_path)

# 配置参数
samples_per_sec = 11025
bits = 16

println("=" ^ 60)
println("生成所有SSTV格式音频文件")
println("=" ^ 60)
println()

println("灰度模式")
println("-" ^ 60)

println("1. Robot8BW (160x120)...")
try
    sstv = Robot8BW(img, samples_per_sec, bits)
    write_wav(sstv, "output_robot8bw.wav")
    println("   ✓ 已保存到 output_robot8bw.wav")
catch e
    println("   ✗ 错误: $e")
end

println("2. Robot24BW (320x240)...")
try
    sstv = Robot24BW(img, samples_per_sec, bits)
    write_wav(sstv, "output_robot24bw.wav")
    println("   ✓ 已保存到 output_robot24bw.wav")
catch e
    println("   ✗ 错误: $e")
end

println()

println("彩色模式")
println("-" ^ 60)

println("3. Robot36 (320x240)...")
try
    sstv = Robot36(img, samples_per_sec, bits)
    write_wav(sstv, "output_robot36.wav")
    println("   ✓ 已保存到 output_robot36.wav")
catch e
    println("   ✗ 错误: $e")
end

println("4. Martin M1 (320x256)...")
try
    sstv = MartinM1(img, samples_per_sec, bits)
    write_wav(sstv, "output_martin_m1.wav")
    println("   ✓ 已保存到 output_martin_m1.wav")
catch e
    println("   ✗ 错误: $e")
end

println("5. Martin M2 (160x256)...")
try
    sstv = MartinM2(img, samples_per_sec, bits)
    write_wav(sstv, "output_martin_m2.wav")
    println("   ✓ 已保存到 output_martin_m2.wav")
catch e
    println("   ✗ 错误: $e")
end

println("6. Scottie S1 (320x256)...")
try
    sstv = ScottieS1(img, samples_per_sec, bits)
    write_wav(sstv, "output_scottie_s1.wav")
    println("   ✓ 已保存到 output_scottie_s1.wav")
catch e
    println("   ✗ 错误: $e")
end

println("7. Scottie S2 (160x256)...")
try
    sstv = ScottieS2(img, samples_per_sec, bits)
    write_wav(sstv, "output_scottie_s2.wav")
    println("   ✓ 已保存到 output_scottie_s2.wav")
catch e
    println("   ✗ 错误: $e")
end

println()

println("PD模式 - YCbCr编码")
println("-" ^ 60)

println("8. PD90 (320x256)...")
try
    sstv = PD90(img, samples_per_sec, bits)
    write_wav(sstv, "output_pd90.wav")
    println("   ✓ 已保存到 output_pd90.wav")
catch e
    println("   ✗ 错误: $e")
end

println("9. PD120 (640x496)...")
try
    sstv = PD120(img, samples_per_sec, bits)
    write_wav(sstv, "output_pd120.wav")
    println("   ✓ 已保存到 output_pd120.wav")
catch e
    println("   ✗ 错误: $e")
end

println("10. PD160 (512x400)...")
try
    sstv = PD160(img, samples_per_sec, bits)
    write_wav(sstv, "output_pd160.wav")
    println("   ✓ 已保存到 output_pd160.wav")
catch e
    println("   ✗ 错误: $e")
end

println("11. PD180 (640x496)...")
try
    sstv = PD180(img, samples_per_sec, bits)
    write_wav(sstv, "output_pd180.wav")
    println("   ✓ 已保存到 output_pd180.wav")
catch e
    println("   ✗ 错误: $e")
end

println("12. PD240 (640x496)...")
try
    sstv = PD240(img, samples_per_sec, bits)
    write_wav(sstv, "output_pd240.wav")
    println("   ✓ 已保存到 output_pd240.wav")
catch e
    println("   ✗ 错误: $e")
end

println("13. PD290 (800x616)...")
try
    sstv = PD290(img, samples_per_sec, bits)
    write_wav(sstv, "output_pd290.wav")
    println("   ✓ 已保存到 output_pd290.wav")
catch e
    println("   ✗ 错误: $e")
end
