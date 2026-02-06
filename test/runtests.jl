"""
SSTV.jl 测试套件
"""

using Test
using SSTV
using Images

@testset "SSTV基础功能测试" begin
    # 创建一个简单的测试图像
    img = zeros(RGB{Float32}, 10, 10)
    for y in 1:10
        for x in 1:10
            img[y, x] = RGB(0.5, 0.5, 0.5)
        end
    end
    
    @testset "Robot8BW创建" begin
        sstv = Robot8BW(img)
        @test sstv.samples_per_sec == 11025
        @test sstv.bits == 16
        @test SSTV.get_vis_code(sstv) == 0x02
    end
    
    @testset "Robot24BW创建" begin
        sstv = Robot24BW(img)
        @test SSTV.get_vis_code(sstv) == 0x0A
    end
    
    @testset "Robot36创建" begin
        sstv = Robot36(img)
        @test SSTV.get_vis_code(sstv) == 0x08
    end
    
    @testset "MartinM1创建" begin
        sstv = MartinM1(img)
        @test SSTV.get_vis_code(sstv) == 0x2c
    end
    
    @testset "MartinM2创建" begin
        sstv = MartinM2(img)
        @test SSTV.get_vis_code(sstv) == 0x28
    end
    
    @testset "ScottieS1创建" begin
        sstv = ScottieS1(img)
        @test SSTV.get_vis_code(sstv) == 0x3c
    end
    
    @testset "ScottieS2创建" begin
        sstv = ScottieS2(img)
        @test SSTV.get_vis_code(sstv) == 0x38
    end
    
    @testset "频率转换" begin
        @test SSTV.byte_to_freq(0x00) ≈ 1500.0  # 黑色
        @test SSTV.byte_to_freq(0xFF) ≈ 2300.0  # 白色
        # 0x80 (128) = 1500 + 800 * 128/255 ≈ 1901.57
        @test SSTV.byte_to_freq(0x80) ≈ 1901.57 atol=0.1  # 中间值
    end
    
    @testset "VOX功能" begin
        sstv = Robot36(img)
        @test sstv.vox_enabled == false
        SSTV.enable_vox!(sstv)
        @test sstv.vox_enabled == true
        SSTV.disable_vox!(sstv)
        @test sstv.vox_enabled == false
    end
    
    @testset "FSKID功能" begin
        sstv = Robot36(img)
        @test sstv.fskid_payload == ""
        SSTV.add_fskid_text!(sstv, "TEST")
        @test length(sstv.fskid_payload) > 0
    end
end

println("所有测试完成！")
