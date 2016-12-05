
export GetHelmholtzOperator,GetHelmholtzOperator,GetHelmholtzShiftOP,getABL,getSommerfeldBC,getHelmholtzFun

function GetHelmholtzOperator(Msh::RegularMesh, mNodal::Array{Float64}, omega::Float64, gamma::Array{Float64},
									NeumannAtFirstDim::Bool,ABLpad::Array{Int64},ABLamp::Float64,Sommerfeld::Bool)
if gamma == []
	gamma = getABL(Msh,NeumannAtFirstDim,ABLpad,ABLamp);
else
	gamma += getABL(Msh,NeumannAtFirstDim,ABLpad,ABLamp);
end
H = GetHelmholtzOperator(Msh, mNodal, omega, gamma, NeumannAtFirstDim,Sommerfeld);
return H,gamma
end

function GetHelmholtzOperator(Msh::RegularMesh, mNodal::Array{Float64}, omega::Float64, gamma::Array{Float64},
							  NeumannAtFirstDim::Bool,Sommerfeld::Bool)
Lap   = getNodalLaplacianMatrix(Msh);
# this code computes a laplacian the long way, AND stores the gradient on Msh... So we avoid using it.
# Grad  = getNodalGradientMatrix(Msh) 
# Lap   = Grad'*Grad

mass = ((-omega^2).*(mNodal[:]).*(1+1im*gamma[:]));
if Sommerfeld
	# println("Adding Sommerfeld");
	somm = getSommerfeldBC(Msh,mNodal,omega,NeumannAtFirstDim);
	mass += somm[:];
end
H = Lap + spdiagm(mass);
return H;
end

function GetHelmholtzShiftOP(mNodal::Array{Float64}, omega::Float64,shift::Float64)
return spdiagm(-mNodal[:].*(1im*shift*omega^2));
end


function getHelmholtzFun(ShiftedHelmholtT::SparseMatrixCSC,ShiftMat::SparseMatrixCSC,numCores::Int64)
function Hfun(alpha,x,beta,y)
		# # here we avoid the storage of the Helmholtz matrix by using the shifted matrix minus the shift.
		One = one(Complex128);
		SpMatMul(alpha,ShiftedHelmholtT,x,beta,y,numCores);
		SpMatMul(alpha,ShiftMat,x,One,y,numCores);
		return y;
end
return Hfun;
end

function getABL(Msh::RegularMesh,NeumannAtFirstDim::Bool,ABLpad::Array{Int64},ABLamp::Float64)
  h = Msh.h;
  n = Msh.n+1;
  pad = ABLpad;
  ntup = tuple(n...);
  
  if Msh.dim==2
	# x1 = linspace(-1,1,n[1]);
	# x2 = linspace(0,1,n[2]);
	# X1,X2 = ndgrid(x1,x2);
	# padx1 = ABLpad[1];
	# padx2 = ABLpad[2];
	# gammaxL = (X1 - x1[padx1]).^2;
	# gammaxL[padx1+1:end,:] = 0
	# gammaxR = (X1 - x1[end-padx1+1]).^2
	# gammaxR[1:end-padx1,:] = 0

	# gammax = gammaxL + gammaxR
	# gammax = gammax/maximum(gammax);

	# gammaz = (X2 - x2[end-padx2+1]).^2
	# gammaz[:,1:end-padx2] = 0
	# gammaz = gammaz/maximum(gammaz);
	
	# gamma = gammax + gammaz
	# gamma *= ABLamp;
	# gamma[gamma.>=ABLamp] = ABLamp;

	gamma = zeros(ntup);
	b_bwd1 = ((pad[1]:-1:1).^2)./pad[1]^2;
	b_bwd2 = ((pad[2]:-1:1).^2)./pad[2]^2;
  
	b_fwd1 = ((1:pad[1]).^2)./pad[1]^2;
	b_fwd2 = ((1:pad[2]).^2)./pad[2]^2;
	I1 = (n[1] - pad[1] + 1):n[1];
	I2 = (n[2] - pad[2] + 1):n[2];
  
	if NeumannAtFirstDim==false
		gamma[:,1:pad[2]] += ones(n[1],1)*b_bwd2';
		gamma[1:pad[1],1:pad[2]] -= b_bwd1*b_bwd2';
		gamma[I1,1:pad[2]] -= b_fwd1*b_bwd2';
	end

	gamma[:,I2] +=  ones(n[1],1)*b_fwd2';
	gamma[1:pad[1],:] += b_bwd1*ones(1,n[2]);
	gamma[I1,:] += b_fwd1*ones(1,n[2]);
	gamma[1:pad[1],I2] -= b_bwd1*b_fwd2';
	gamma[I1,I2] -= b_fwd1*b_fwd2';
	gamma *= ABLamp;
	# figure()
	# imshow(gamma'); colorbar()
	
  else
	x1 = linspace(-1,1,n[1]);
	x2 = linspace(-1,1,n[2]);
	x3 = linspace( 0,1,n[3]);
	X1,X2,X3 = ndgrid(x1,x2,x3);
	padx1 = ABLpad[1];
	padx2 = ABLpad[2];
	padx3 = ABLpad[3];
	gammaL = (X1 - x1[padx1]).^2;
	gammaL[padx1+1:end,:,:] = 0.0
	gammaR = (X1 - x1[end-padx1+1]).^2
	gammaR[1:end-padx1,:,:] = 0.0
	
	gammat = gammaL + gammaR;
	gammat = gammat/maximum(gammat);
	gamma = copy(gammat);
	gammat[:] = 0.0;

	gammaL = (X2 - x2[padx2]).^2;
	gammaL[:,padx2+1:end,:] = 0.0
	gammaR = (X2 - x2[end-padx2+1]).^2
	gammaR[:,1:end-padx2,:] = 0.0
	
	gammat = gammaL + gammaR
	gammat = gammat/maximum(gammat);
	gamma += gammat;

	gammat = (X3 - x3[end-padx3+1]).^2
	gammat[:,:,1:end-padx3] = 0.0
	gammat = gammat/maximum(gammat);
	gamma += gammat;
	gamma *= ABLamp;
	gamma[gamma.>=ABLamp] = ABLamp;
  end
  return gamma;
end

function getSommerfeldBC(Msh::RegularMesh,mNodal::Array{Float64}, omega::Float64,NeumannOnTop::Bool)

ntup = tuple((Msh.n+1)...);
Somm = zeros(Complex128,ntup);
mNodal = reshape(mNodal,ntup);
h = Msh.h;

if Msh.dim==2
	if NeumannOnTop
		Somm[2:end-1,1] = 0.0;
	else
		Somm[2:end-1,1] = -1im*omega*(1/h[2]).*sqrt(mNodal[2:end-1,1]);
	end
	Somm[1:end,end] = (-1im*omega*(1/h[2])).*sqrt(mNodal[1:end,end]);
	Somm[end,:] += (-1im*omega*(1/h[1])).*sqrt(mNodal[end,:]);
	Somm[1,:] += (-1im*omega*(1/h[1])).*sqrt(mNodal[1,:]);
else
	Somm[2:end-1,2:end-1,2:end-1] = 0.0;
	if NeumannOnTop
		Somm[2:end-1,2:end-1,1] = 0.0;
	else
		Somm[2:end-1,2:end-1,1] .* -1im*omega*(2/h[3]);
	end
	Somm[:,1,:] .* -1im*omega*(2/h[2]);
	Somm[:,end,:] .* -1im*omega*(2/h[2]);
	Somm[1,:,:] .* -1im*omega*(2/h[1]);
	Somm[end,:,:] .* -1im*omega*(2/h[1]);
end
return Somm;
end