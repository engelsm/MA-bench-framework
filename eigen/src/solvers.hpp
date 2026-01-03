#pragma once
#include "util.hpp"

inline Scalar power_iteration(const CustomSparseMatrix &A, int max_iter = 20)
{
	const int n = static_cast<int>(A.rows());

	CustomVector v = CustomVector::Random(n);
	CustomVector v_next = CustomVector::Zero(n);
	v.normalize();

	Scalar lambda = 0.0;

	for (int i = 0; i < max_iter; ++i)
	{

		spmv(A, v, v_next);
		lambda = v.dot(v_next);

		Scalar norm = v_next.norm();

		v = v_next / norm;
	}

	std::cout << "  Estimated Lambda = " << lambda << std::endl;

	return lambda;
}