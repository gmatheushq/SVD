include("svd_funcoes.jl")
using .SVD_funcoes
using FileIO, LinearAlgebra

if isempty(ARGS) #
    println("julia main.jl imagem.formato")
    exit(1) 
end

for path in ARGS 
    println("\n", "="^70)
    println("Processando: $path")
    println("="^70)

    img = try
        load(path) 
    catch e
        @warn "Erro ao carregar '$path': $e" 
        continue
    end

    base_name  = splitext(basename(path))[1]
    output_dir = joinpath("resultados_svd", base_name)
   
    gray_by_type    = is_grayscale_image(img)
    gray_by_content = !gray_by_type && is_effectively_grayscale(img)
    is_gray = gray_by_type || gray_by_content

    if is_gray
        println("Tipo: PB")

        A = extract_gray_matrix(img)
        m, n = size(A)
        raw_bytes = raw_storage_bytes_gray(m, n) 
        println("Calculando SVD")

        t0 = time()
        F  = svd(A)
      
        svd_time = time() - t0
        svd_bytes_fn = k -> svd_real_bytes_gray(F.U, F.S, F.V, k)

        process_image(
            [A], "PB",
            [F.U], [F.S], [F.V],
            base_name, output_dir,
            x -> to_gray_image(x),
            raw_bytes, svd_bytes_fn,
            svd_time
        )

    else
        println("Tipo: RGB")

        R, G, B = extract_rgb_channels(img)
        m, n = size(R)
        raw_bytes = raw_storage_bytes_rgb(m, n)

        println("Calculando SVD")

        t0 = time()
        Fr = svd(R)
        Fg = svd(G)
        Fb = svd(B)
        svd_time = time() - t0
        U_list = [Fr.U, Fg.U, Fb.U]
        S_list = [Fr.S, Fg.S, Fb.S]
        V_list = [Fr.V, Fg.V, Fb.V]
        svd_bytes_fn = k -> svd_real_bytes_rgb(U_list, S_list, V_list, k)

        process_image(
            [R, G, B], "RGB",
            U_list, S_list, V_list,
            base_name, output_dir,
            (r, g, b) -> to_rgb_image(r, g, b),
            raw_bytes, svd_bytes_fn,
            svd_time
        )
    end
end

