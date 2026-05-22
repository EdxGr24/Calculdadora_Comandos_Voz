-- filtro_fir.vhd
--Filtro FIR pasa-banda 300-3400 Hz
--Orden 32 * 33 coeficientes punto fijo Q1.15

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity filtro_fir is
    port (
        CLK_SYS         : in std_logic;
        RST             : in std_logic;
        -- Entradas Controlador I2s
        entrada_dato    : in std_logic_vector(15 downto 0);
        entrada_valido  : in std_logic;  -- '1' un ciclo cuando hay una muestra nueva

        -- Salidas hacia la FFT y VAD
        salida_dato     : out std_logic_vector(15 downto 0);
        salida_valido   : out std_logic
    );
end entity filtro_fir;

architecture rtl of filtro_fir is

-- Parámetros del Filtro --
constant ORDEN_FILTRO   : integer := 32;
constant NUM_COEFS      : integer := ORDEN_FILTRO + 1; --33

-- Tipos --
type t_coeficientes is array(0 to ORDEN_FILTRO)
    of signed(15 downto 0);

type t_buffer is array(0 to ORDEN_FILTRO)
    of signed(15 downto 0);

-- Coeficientes Q1.15 --
-- Reemplazar datos con el script de python
-- pasa-banda 300-3400 Hz  a 16 Khz con ventana Hamming

constant COEFICIENTES : t_coeficientes := (
     0 => to_signed(   -19, 16), -- -0.000577),
     1 => to_signed(    -4, 16), -- -0.000107),
     2 => to_signed(   -99, 16), -- -0.003010),
     3 => to_signed(  -252, 16), -- -0.007684),
     4 => to_signed(  -242, 16), -- -0.007371),
     5 => to_signed(   -30, 16), -- -0.000902),
     6 => to_signed(   -82, 16), -- -0.002506),
     7 => to_signed(  -726, 16), -- -0.022171),
     8 => to_signed( -1237, 16), -- -0.037742),
     9 => to_signed(  -614, 16), -- -0.018744),
    10 => to_signed(   420, 16), -- 0.012823),
    11 => to_signed(  -286, 16), -- -0.008739),
    12 => to_signed( -2844, 16), -- -0.086794),
    13 => to_signed( -3542, 16), -- -0.108090),
    14 => to_signed(  1108, 16), -- 0.033805),
    15 => to_signed(  8820, 16), -- 0.269164),
    16 => to_signed( 12673, 16), -- 0.386735),
    17 => to_signed(  8820, 16), -- 0.269164),
    18 => to_signed(  1108, 16), -- 0.033805),
    19 => to_signed( -3542, 16), -- -0.108090),
    20 => to_signed( -2844, 16), -- -0.086794),
    21 => to_signed(  -286, 16), -- -0.008739),
    22 => to_signed(   420, 16), -- 0.012823),
    23 => to_signed(  -614, 16), -- -0.018744),
    24 => to_signed( -1237, 16), -- -0.037742),
    25 => to_signed(  -726, 16), -- -0.022171),
    26 => to_signed(   -82, 16), -- -0.002506),
    27 => to_signed(   -30, 16), -- -0.000902),
    28 => to_signed(  -242, 16), -- -0.007371),
    29 => to_signed(  -252, 16), -- -0.007684),
    30 => to_signed(   -99, 16), -- -0.003010),
    31 => to_signed(    -4, 16), -- -0.000107),
  32 => to_signed(   -19, 16) -- -0.000577);
);

-- Buffer de muestras (línea de retardo)
-- Guarda las últimas 33 muestras del audio
signal buffer_muestras : t_buffer := (others => (others => '0'));

-- Señales internas
signal acumulador      : signed(39 downto 0) := (others => '0');
signal contador        : integer range 0 to NUM_COEFS := 0;
signal calculando      : std_logic := '0';

begin 

-- Proceso principal filtro FIR
    -- Un filtro FIR es básicamente una convolución:
    -- y[n] = Σ h[k] × x[n-k]  para k = 0 a 32
    --
    -- Donde:
    --   y[n]  = muestra de salida actual
    --   h[k]  = coeficiente k del filtro
    --   x[n-k]= muestra de entrada de hace k pasos
    --
    -- En hardware esto se implementa con:
    --   1. Un buffer de desplazamiento (las últimas 33 muestras)
    --   2. 33 multiplicaciones
    --   3. Una suma acumulada de los 33 productos


proc_fir: process(CLK_SYS)
    variable producto : signed(31 downto 0);
begin
    if rising_edge(CLK_SYS) then
        if RST = '1' then
            buffer_muestras <= (others => (others => '0'));
            acumulador      <= (others => '0');
            contador        <= 0;
            calculando      <= '0';
            salida_valido   <= '0';
            salida_dato     <= (others => '0');
            
        else
            -- Salida no válida por defecto
            salida_valido <= '0';
            -- Fase 1: LLegó muestra nueva desde el I2S
            -- Mover muestra al buffer y desplazar las anteriores una posicion a la derecha
            if entrada_valido = '1' then
                -- desplazamiento del buffer 
                for i in ORDEN_FILTRO downto 1 loop         
                    buffer_muestras(i) <= buffer_muestras(i-1);
                end loop;
                buffer_muestras(0) <= signed(entrada_dato);
                
                -- Iniciar calculo convolucion
                acumulador <= (others => '0');
                contador   <= 0;
                calculando <= '1';

            end if;
            
            -- Fase 2: Calcular convolucion
            if calculando = '1' then
                -- Multiplicar coeficiente * muestra del valor del buffer   
                --producto = 16 bits * 16 bits
            producto := COEFICIENTES(contador) * buffer_muestras(contador);
            acumulador <= acumulador + resize(producto(30 downto 15), 40);
            
                if contador = ORDEN_FILTRO then
                    -- convolucion completa
                    calculando  <= '0';
                    contador    <= 0;

                    -- Saturar resultado a 16 bits
                    if acumulador > to_signed(32767, 40) then 
                        salida_dato <= std_logic_vector(to_signed(3276, 16));
                    elsif acumulador < to_signed(-32768, 40) then
                        salida_dato <= std_logic_vector(to_signed(-32768, 16));
                    else
                        salida_dato <= std_logic_vector(acumulador(15 downto 0));
                    end if;
                    
                    salida_valido <= '1';
                else
                    contador <= contador + 1;
                end if;
            end if;

        end if;
    end if;
end process proc_fir;

end architecture rtl;