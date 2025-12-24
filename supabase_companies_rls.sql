-- Enable RLS for companies table
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

-- Allow everyone (authenticated) to read companies
CREATE POLICY "Enable read access for authenticated users" 
ON companies FOR SELECT 
TO authenticated 
USING (true);

-- Allow admins to insert/update/delete (assuming you have a profiles table with roles)
CREATE POLICY "Enable insert for admins only" 
ON companies FOR INSERT 
TO authenticated 
WITH CHECK (
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
);

CREATE POLICY "Enable update for admins only" 
ON companies FOR UPDATE 
TO authenticated 
USING (
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
)
WITH CHECK (
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
);

CREATE POLICY "Enable delete for admins only" 
ON companies FOR DELETE 
TO authenticated 
USING (
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
);
