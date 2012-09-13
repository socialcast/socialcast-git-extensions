require "spec_helper"

describe Socialcast::Gitx::Git do

  subject do
    Object.new.tap do |obj|
      class << obj
        include Socialcast::Gitx::Git
      end
    end
  end


  describe "retained_branch_name method" do
    it "should return 'backport_' prefixed to the old branch name" do
      subject.send(:retained_branch_name, 'foobar').should == "backport_foobar"
    end
  end

  describe "retained_branch? method" do
    it "should return false for branches not prefixed with 'backport_'" do
      subject.send(:retained_branch?, 'foobar').should be_false
    end
    it "should return true for branches prefixed with 'backport_'" do
      subject.send(:retained_branch?, 'backport_foobar').should be_true
    end
  end

  describe "reserved_branch? method" do
    %w{ master next_release HEAD }.each do |special_branch|
       it "should return true for the #{special_branch} branch" do
         subject.send(:reserved_branch?, special_branch).should be_true
       end
    end
    it "should return false for arbitrary branches" do
      subject.send(:reserved_branch?, "foobar").should be_false
    end
  end

  describe "aggregate_branch? method" do
    %w{ staging prototype last_known_good_foobar }.each do |aggregate_branch|
       it "should return true for the #{aggregate_branch} branch" do
         subject.send(:aggregate_branch?, aggregate_branch).should be_true
       end
    end
    it "should return false for arbitrary branches" do
      subject.send(:aggregate_branch?, "foobar").should be_false
    end
  end

  describe "protected_branch?" do
    it "should return false if the branch is not retained, aggregate or reserved" do
      subject.stub(:retained_branch? => false, :aggregate_branch? => false, :reserved_branch? => false)
      subject.send(:protected_branch?, "foobar").should be_false
    end
    it "should return true if the branch is retained" do
      subject.stub(:retained_branch? => true, :aggregate_branch? => false, :reserved_branch? => false)
      subject.send(:protected_branch?, "foobar").should be_true
    end
    it "should return true if the branch is aggregate" do
      subject.stub(:retained_branch? => false, :aggregate_branch? => true, :reserved_branch? => false)
      subject.send(:protected_branch?, "foobar").should be_true
    end
    it "should return true if the branch is reserved" do
      subject.stub(:retained_branch? => false, :aggregate_branch? => false, :reserved_branch? => true)
      subject.send(:protected_branch?, "foobar").should be_true
    end
  end

  describe "assert_not_protected_branch! method" do
    it "should raise an error if the branch is a protected branch" do
      subject.stub(:protected_branch? => true)
      expect { subject.send :assert_not_protected_branch!, "foobar", "noop" }.to raise_error
    end
    it "should not raise an error if the branch is not a protected branch" do
      subject.stub(:protected_branch? => false)
      expect { subject.send :assert_not_protected_branch!, "foobar", "noop" }.to_not raise_error
    end
  end

end
