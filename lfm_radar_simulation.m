fs = 40e6;              % Sampling frequency (40 MHz)
T = 10e-6;              % Pulse duration (10 us)
f1 = 5e6;          % Aliased start frequency
f2 = 15e6;           % Aliased end frequency       

% 1. Generate Reference Chirp (Up-Chirp)
t = 0:1/fs:T-1/fs; 


K= (f2-f1)/T;
chirp_sig = exp(1j* 2* pi *( f1 * t + 0.5*K * t.^2));
fc = 8e6;
lpf= designfilt('lowpassfir', 'FilterOrder',40,'CutoffFrequency',fc,'SampleRate',fs);
coeffs=lpf.Coefficients;
coeffs = coeffs/max(abs(coeffs));

filtered_chirp = filter(lpf, chirp_sig);
pc_coeff= conj(fliplr(filtered_chirp));

N=length(filtered_chirp);
freqs=linspace(-fs/2, fs/2 - fs/N, N)/1e6;
fft_data = fftshift(fft(filtered_chirp))/N;
amplitude = abs (fft_data);

figure;
plot(freqs,amplitude);
hold on;
title('complex lpf filtered chirp');
xlabel('Frequency(MHz)');
ylabel('Amplitude');
grid on;

pc_coeff = pc_coeff/max(abs(pc_coeff));
pc_real = real (pc_coeff);
pc_imag = imag(pc_coeff);

figure;
plot(t,real(chirp_sig));
grid on;
xlabel('Time(seconds)');
ylabel('Amplitude');
title('chirp_signal');

figure;
plot(t,real(filtered_chirp));
grid on;
xlabel('Time(seconds)');
ylabel('Amplitude');
title('filtered_chirp');

figure;
plot(t,real(pc_real));
grid on;
xlabel('Time(seconds)');
ylabel('Amplitude');
title('pc_real');

figure;
plot(t,real(pc_imag));
grid on;
xlabel('Time(seconds)');
ylabel('Amplitude');
title('pc_imag');

rx=filtered_chirp;
pc_outreal=conv(rx,pc_real);
pc_outimag=conv(rx,pc_imag);
% plot(abs(pc_outreal));
% plot(abs(pc_outimag));

l1 =length(pc_outreal);
l2 = length(pc_outimag);

y1=fft(pc_outreal);
y2=fft(pc_outimag);

pr2=abs(y1/l1);
pr1=pr2(1:floor(l1/2)+1);
pr1(2:end-1)=2*pr1(2:end-1);

pi2=abs(y2/l2);
pi1=pi2(1:floor(l2/2)+1);
pi1(2:end-1)=2*pi1(2:end-1);

freal=(0:floor(l1/2))*(fs/l1);
fimag=(0:floor(l2/2))*(fs/l2);

figure;
plot(freal,pr1);
xlabel('Frequency(Hz)');
ylabel('Amplitude');
title('pc_outreal');
grid on;

figure;
plot(fimag,pi1);
grid on;
xlabel('Frequency(Hz)');
ylabel('Amplitude');
title('pc_outimag');
